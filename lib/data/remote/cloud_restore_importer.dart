import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/permission.dart';
import '../local/database/database.dart';

/// Rehydrates portable business data from the server restore snapshot.
///
/// The restore is destructive and transactional: all portable business rows
/// and reconstructible staff identities are replaced together. Device-only
/// state (printers, notifications, diagnostics, carts and sync queue) is not
/// imported because it belongs to the physical installation, not the cloud
/// business.
class CloudRestoreImporter {
  CloudRestoreImporter(this._db);

  final AppDatabase _db;

  static const _tableMap = <String, String>{
    'locations': 'locations',
    'products': 'products',
    'categories': 'categories',
    'suppliers': 'suppliers',
    'customers': 'customers',
    'sales': 'sales',
    'sale_items': 'sale_items',
    'sale_payments': 'sale_payments',
    'product_stock_levels': 'product_stock_levels',
    'customer_ledger_entries': 'customer_ledger_entries',
    'inventory_movements': 'stock_movements',
    'expense_categories': 'expense_categories',
    'expenses': 'expenses',
    'income_records': 'income_records',
    'supplier_ledger_entries': 'supplier_ledger_entries',
    'returns': 'return_requests',
    'return_items': 'return_items',
    'tax_remittances': 'tax_remittances',
    'cash_drawer_shifts': 'cash_drawer_shifts',
    'audit_events': 'audit_logs',
  };

  static const _clearOrder = <String>[
    'attendance_records',
    'leave_records',
    'user_permissions',
    'employees',
    'sessions',
    'return_items',
    'sale_payments',
    'sale_items',
    'customer_ledger_entries',
    'supplier_ledger_entries',
    'product_stock_levels',
    'stock_movements',
    'return_requests',
    'cash_drawer_shifts',
    'tax_remittances',
    'income_records',
    'expenses',
    'expense_categories',
    'sales',
    'customers',
    'suppliers',
    'categories',
    'products',
    'locations',
    'audit_logs',
    'users',
  ];

  static const _importOrder = <String>[
    'locations',
    'categories',
    'suppliers',
    'customers',
    'products',
    'sales',
    'expense_categories',
    'expenses',
    'income_records',
    'tax_remittances',
    'cash_drawer_shifts',
    'stock_movements',
    'product_stock_levels',
    'customer_ledger_entries',
    'supplier_ledger_entries',
    'sale_items',
    'sale_payments',
    'return_requests',
    'return_items',
    'audit_logs',
    'users',
  ];

  Future<CloudRestoreResult> importSnapshot(
    Map<String, dynamic> snapshot, {
    String? ownerCloudUserId,
    bool transactional = true,
    bool preserveUnexportedLocalTables = false,
    void Function(String status)? onProgress,
  }) async {
    final version = snapshot['version'];
    if (version is! num || version.toInt() < 3) {
      throw const FormatException('Unsupported Fulus restore snapshot version.');
    }

    final importedCounts = <String, int>{};
    final expectedCounts = <String, int>{};

    Future<void> runImport() async {
      onProgress?.call('Clearing existing local business data…');
      await _clearPortableData(preserveUnexportedLocalTables: preserveUnexportedLocalTables);

      final tableInfoCache = <String, _TableInfo>{};
      for (final localTable in _importOrder) {
        final remoteKey = _tableMap.entries
            .firstWhere((entry) => entry.value == localTable,
                orElse: () => const MapEntry('', ''))
            .key;
        if (remoteKey.isEmpty) continue;
        final raw = snapshot[remoteKey];
        if (raw == null) continue;
        if (raw is! List) {
          throw FormatException('$remoteKey must be an array in a restore snapshot.');
        }
        expectedCounts[remoteKey] = raw.length;
        if (raw.isEmpty) {
          importedCounts[remoteKey] = 0;
          onProgress?.call('${_restoreLabel(remoteKey)}: 0 rows');
          continue;
        }

        final info = tableInfoCache[localTable] ??= await _readTableInfo(localTable);
        if (info.columns.isEmpty) {
          throw StateError('Local restore table "$localTable" does not exist.');
        }

        var count = 0;
        onProgress?.call('Restoring ${_restoreLabel(remoteKey)} (0/${raw.length})…');
        for (final value in raw) {
          if (value is! Map) {
            throw FormatException('$remoteKey contains a non-object row.');
          }
          await _insertRow(localTable, info, Map<String, dynamic>.from(value));
          count++;
          if (count == raw.length || count % 10 == 0) {
            onProgress?.call('Restoring ${_restoreLabel(remoteKey)} ($count/${raw.length})…');
          }
        }
        importedCounts[remoteKey] = count;
      }

      onProgress?.call('Restoring staff and permissions…');
      final staffCounts = await _restoreStaff(
        snapshot,
        ownerCloudUserId: ownerCloudUserId,
      );
      expectedCounts.addAll(staffCounts.expected);
      importedCounts.addAll(staffCounts.imported);

      onProgress?.call('Verifying restored row counts…');
      await _verifyCounts(expectedCounts, importedCounts, preserveUnexportedLocalTables: preserveUnexportedLocalTables);
      onProgress?.call('Verifying restored database integrity…');
      await _verifyForeignKeys();
    }

    if (transactional) {
      await _db.transaction(runImport);
    } else {
      await runImport();
    }

    return CloudRestoreResult(
      importedCounts,
      expectedCounts: expectedCounts,
    );
  }

  String _restoreLabel(String remoteKey) => switch (remoteKey) {
        'sale_items' => 'sale items',
        'sale_payments' => 'sale payments',
        'product_stock_levels' => 'stock levels',
        'customer_ledger_entries' => 'customer ledger',
        'inventory_movements' => 'stock movements',
        'expense_categories' => 'expense categories',
        'supplier_ledger_entries' => 'supplier ledger',
        'cash_drawer_shifts' => 'cash drawer shifts',
        'audit_events' => 'audit events',
        _ => remoteKey,
      };

  Future<_StaffRestoreCounts> _restoreStaff(
    Map<String, dynamic> snapshot, {
    String? ownerCloudUserId,
  }) async {
    final memberships = _maps(snapshot['business_memberships']);
    final profiles = <String, Map<String, dynamic>>{
      for (final profile in _maps(snapshot['profiles']))
        if (profile['id'] != null) profile['id'].toString(): profile,
    };
    final roles = <String, Map<String, dynamic>>{
      for (final role in _maps(snapshot['roles']))
        if (role['id'] != null) role['id'].toString(): role,
    };
    final permissions = <String, String>{
      for (final permission in _maps(snapshot['permissions']))
        if (permission['id'] != null && permission['code'] != null)
          permission['id'].toString(): permission['code'].toString(),
    };
    final rolePermissions = _maps(snapshot['role_permissions']);
    final permissionCodesByRole = <String, Set<String>>{};
    for (final row in rolePermissions) {
      final roleId = row['role_id']?.toString();
      final permissionId = row['permission_id']?.toString();
      final code = permissionId == null ? null : permissions[permissionId];
      if (roleId != null && code != null) {
        permissionCodesByRole.putIfAbsent(roleId, () => <String>{}).add(code);
      }
    }

    final locationMemberships = _maps(snapshot['location_memberships']);
    final locationByUser = <String, String>{};
    for (final row in locationMemberships) {
      if (row['status']?.toString() != 'active') continue;
      final userId = row['user_id']?.toString();
      final locationId = row['location_id']?.toString();
      if (userId != null && locationId != null) {
        locationByUser.putIfAbsent(userId, () => locationId);
      }
    }

    var users = 0;
    var employees = 0;
    var permissionRows = 0;
    final now = DateTime.now();

    for (final membership in memberships) {
      final userId = membership['user_id']?.toString();
      if (userId == null || userId == ownerCloudUserId) continue;

      final profile = profiles[userId] ?? <String, dynamic>{};
      final role = roles[membership['role_id']?.toString() ?? ''];
      final roleName = role?['name']?.toString() ?? 'employee';
      final fullName = profile['full_name']?.toString().trim();
      final safeName = fullName?.isNotEmpty == true ? fullName! : 'Staff member';
      final email = profile['email']?.toString();

      await _insertUser(
        userId: userId,
        fullName: safeName,
        email: email,
        now: now,
      );
      users++;

      final membershipId = membership['id']?.toString() ?? userId;
      await _insertEmployee(
        employeeId: membershipId,
        userId: userId,
        fullName: safeName,
        email: email,
        role: roleName,
        locationId: locationByUser[userId],
        isActive: membership['status']?.toString() == 'active',
        createdAt: _dateOrNow(membership['created_at'], now),
        updatedAt: _dateOrNow(membership['updated_at'], now),
      );
      employees++;

      final localPermissions = _mapCloudPermissions(
        permissionCodesByRole[membership['role_id']?.toString() ?? ''] ?? const {},
      );
      for (final permission in localPermissions) {
        await _insertPermission(
          userId: userId,
          permission: permission,
          grantedAt: now,
        );
        permissionRows++;
      }
    }

    return _StaffRestoreCounts(
      expected: {
        'restored_staff_users': users,
        'restored_employees': employees,
        'restored_user_permissions': permissionRows,
      },
      imported: {
        'restored_staff_users': users,
        'restored_employees': employees,
        'restored_user_permissions': permissionRows,
      },
    );
  }

  Future<void> _insertUser({
    required String userId,
    required String fullName,
    required String? email,
    required DateTime now,
  }) async {
    final values = <String, Object?>{
      'local_id': userId,
      'full_name': fullName,
      'email': email,
      'role': 'employee',
      'is_active': 1,
      'failed_login_attempts': 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    };
    await _insertValues('users', values);
  }

  Future<void> _insertEmployee({
    required String employeeId,
    required String userId,
    required String fullName,
    required String? email,
    required String role,
    required String? locationId,
    required bool isActive,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final values = <String, Object?>{
      'id': employeeId,
      'auth_user_id': userId,
      'full_name': fullName,
      'role': role,
      'email': email,
      'location_id': locationId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
    await _insertValues('employees', values);
  }

  Future<void> _insertPermission({
    required String userId,
    required Permission permission,
    required DateTime grantedAt,
  }) async {
    await _insertValues('user_permissions', {
      'user_id': userId,
      'permission': permission.name,
      'granted_at': grantedAt.millisecondsSinceEpoch,
    });
  }

  Set<Permission> _mapCloudPermissions(Set<String> codes) {
    final result = <Permission>{};
    for (final code in codes) {
      if (code == 'audit.read') result.add(Permission.viewAuditLog);
      if (code == 'business.manage' || code == 'locations.manage') {
        result.add(Permission.manageSettings);
      }
      if (code == 'business.read') result.add(Permission.viewDashboardStats);
      if (code == 'cash.manage' || code == 'cash.read' ||
          code == 'finance.manage' || code == 'finance.read' ||
          code == 'sales.read' || code == 'customers.read' ||
          code == 'credit.manage') {
        result.add(Permission.viewMoney);
      }
      if (code == 'catalog.manage' || code == 'inventory.adjust' ||
          code == 'inventory.transfer' || code == 'inventory.read') {
        result.add(Permission.manageStock);
      }
      if (code == 'reports.read') result.add(Permission.viewReports);
      if (code == 'employees.manage') result.add(Permission.manageEmployees);
      if (code == 'returns.approve' || code == 'sales.void') {
        result.add(Permission.approveWithoutSupervisor);
      }
    }
    return result;
  }

  Future<void> _verifyCounts(
    Map<String, int> expected,
    Map<String, int> imported, {
    required bool preserveUnexportedLocalTables,
  }) async {
    for (final entry in expected.entries) {
      if (entry.value != imported[entry.key]) {
        throw StateError(
          'Restore verification failed for ${entry.key}: expected ${entry.value}, imported ${imported[entry.key] ?? 0}.',
        );
      }
    }

    for (final entry in _tableMap.entries) {
      if (preserveUnexportedLocalTables && !expected.containsKey(entry.key)) continue;
      final raw = await _db.customSelect(
        'SELECT COUNT(*) AS count FROM ${_quoteIdentifier(entry.value)}',
      ).getSingle();
      final actual = raw.read<int>('count');
      if (actual != (expected[entry.key] ?? 0)) {
        throw StateError(
          'Restore verification failed for ${entry.key}: local database contains $actual rows, expected ${expected[entry.key] ?? 0}.',
        );
      }
    }
  }

  Future<void> _verifyForeignKeys() async {
    final rows = await _db.customSelect('PRAGMA foreign_key_check').get();
    if (rows.isNotEmpty) {
      throw StateError(
        'Restore verification failed: ${rows.length} foreign-key violations were detected.',
      );
    }
  }

  Future<void> _clearPortableData({required bool preserveUnexportedLocalTables}) async {
    const preserved = {
      'attendance_records',
      'leave_records',
      'supplier_ledger_entries',
      'tax_remittances',
    };
    for (final table in _clearOrder) {
      if (preserveUnexportedLocalTables && preserved.contains(table)) continue;
      if (await _tableExists(table)) {
        await _db.customStatement('DELETE FROM ${_quoteIdentifier(table)}');
      }
    }
  }

  Future<bool> _tableExists(String table) async {
    final rows = await _db.customSelect(
      'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
      variables: [Variable.withString('table'), Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<_TableInfo> _readTableInfo(String table) async {
    final rows = await _db.customSelect(
      'PRAGMA table_info(${_quoteIdentifier(table)})',
    ).get();
    return _TableInfo(
      rows.map((row) => _ColumnInfo(
        name: row.read<String>('name'),
        type: row.read<String>('type').toUpperCase(),
        notNull: row.read<int>('notnull') == 1,
        hasDefault: row.data['dflt_value'] != null,
      )).toList(growable: false),
    );
  }

  Future<void> _insertRow(
    String table,
    _TableInfo info,
    Map<String, dynamic> remote,
  ) async {
    final normalizedRemote = _normalizeRemoteRow(table, remote);
    final values = <String, Object?>{};
    for (final column in info.columns) {
      final remoteKey = _remoteKeyForColumn(column.name, normalizedRemote);
      if (remoteKey == null) continue;
      values[column.name] = _coerce(normalizedRemote[remoteKey], column.type);
    }

    final remoteId = normalizedRemote['id']?.toString();
    if (remoteId != null && remoteId.isNotEmpty) {
      if (info.has('local_id')) values['local_id'] = remoteId;
      if (info.has('server_id')) values['server_id'] = remoteId;
      if (info.has('id')) values['id'] = remoteId;
    }
    if (info.has('sync_status') && !values.containsKey('sync_status')) {
      values['sync_status'] = 'settled';
    }
    if (info.has('created_at') && !values.containsKey('created_at')) {
      values['created_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (info.has('updated_at') && !values.containsKey('updated_at')) {
      values['updated_at'] = values['created_at'] ?? DateTime.now().millisecondsSinceEpoch;
    }

    final missing = info.columns
        .where((column) => column.notNull && !column.hasDefault && !values.containsKey(column.name))
        .map((column) => column.name)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError('Cannot restore $table row: missing required columns ${missing.join(', ')}.');
    }
    if (values.isEmpty) throw StateError('Cannot restore an empty $table row.');
    await _insertValues(table, values);
  }

  /// Converts the server's audit-event vocabulary to the local AuditLogs
  /// shape before the generic importer validates required columns.
  ///
  /// The cloud event uses entity_type/entity_id/metadata while the local
  /// audit table deliberately uses module/record_id/details. Keeping this
  /// translation here makes the cloud contract explicit without weakening
  /// the local schema or making AuditLogs.module nullable.
  Map<String, dynamic> _normalizeRemoteRow(
    String table,
    Map<String, dynamic> remote,
  ) {
    final normalized = Map<String, dynamic>.from(remote);

    // The cloud inventory ledger is intentionally delta-based:
    // inventory_movements.quantity_delta is the authoritative server field.
    // The local Drift table is richer because it also records the command
    // vocabulary (in/out/adjustment/sale). Restore therefore needs an
    // explicit compatibility translation rather than assuming the two
    // schemas are identical. New snapshots may already contain the richer
    // fields; older/current production snapshots contain quantity_delta.
    if (table == 'stock_movements') {
      final delta = _asInt(remote['quantity_delta']);
      final operationType = remote['operation_type']?.toString();
      final reason = remote['reason']?.toString() ?? '';

      if (!normalized.containsKey('movement_type')) {
        if (operationType == 'inventory.set' ||
            operationType == 'inventory.adjust') {
          normalized['movement_type'] = 'adjustment';
        } else if (reason.toLowerCase().startsWith('sale ')) {
          normalized['movement_type'] = 'sale';
        } else if (delta != null && delta > 0) {
          normalized['movement_type'] = 'in';
        } else if (delta != null && delta < 0) {
          normalized['movement_type'] = 'out';
        }
      }

      if (!normalized.containsKey('quantity') &&
          delta != null &&
          normalized['movement_type'] != 'adjustment') {
        normalized['quantity'] = delta.abs();
      }

      // Absolute inventory.set commands can be reconstructed exactly from
      // the server's post-command current_stock. For legacy delta
      // adjustments, current_stock is still the authoritative resulting
      // quantity, so preserving it as the local adjustment target avoids
      // fabricating a delta the device cannot safely recompute.
      if (!normalized.containsKey('new_quantity') &&
          normalized['movement_type'] == 'adjustment' &&
          remote['current_stock'] != null) {
        normalized['new_quantity'] = remote['current_stock'];
      }
    }

    if (table == 'sale_payments') {
      // The server stores payment_method/created_at; the local child table
      // deliberately calls those method/recorded_at.
      if (!normalized.containsKey('method') &&
          remote.containsKey('payment_method')) {
        normalized['method'] = remote['payment_method'];
      }
      if (!normalized.containsKey('recorded_at') &&
          remote.containsKey('created_at')) {
        normalized['recorded_at'] = remote['created_at'];
      }
    }

    if (table == 'return_requests') {
      // The server names the parent sale \"sale_id\" while the local
      // return table deliberately uses \"original_sale_local_id\".
      // The generic *_local_id adapter cannot infer this because the
      // local name contains \"original\". Keep the relationship explicit
      // so real production return rows can be restored without weakening
      // the local foreign key.
      if (!normalized.containsKey('original_sale_local_id') &&
          remote.containsKey('sale_id')) {
        normalized['original_sale_local_id'] = remote['sale_id'];
      }

      // The server return ledger is authoritative for sale/reason/amount.
      // Legacy returns predate persisted refund_method and used the cash
      // ledger for refunds, so "cash" is the honest compatibility value.
      if (!normalized.containsKey('return_reason') &&
          remote.containsKey('reason')) {
        normalized['return_reason'] = remote['reason'];
      }
      if (!normalized.containsKey('refund_method')) {
        normalized['refund_method'] =
            remote['refund_method']?.toString() ?? 'cash';
      }
      if (!normalized.containsKey('inventory_restored')) {
        normalized['inventory_restored'] =
            remote['inventory_restored'] ?? remote['status'] == 'completed';
      }
      if (!normalized.containsKey('is_void')) {
        normalized['is_void'] = remote['is_void'] ?? false;
      }
      if (!normalized.containsKey('completed_at') &&
          remote['status'] == 'completed' &&
          remote['created_at'] != null) {
        normalized['completed_at'] = remote['created_at'];
      }
    }

    if (table == 'expenses') {
      // Old server rows may have no location_id because the original
      // expense schema allowed it to be absent. New writes always carry it.
      // The snapshot RPC enriches it from the cash ledger when possible;
      // this client fallback keeps older snapshots importable.
      if (!normalized.containsKey('description') ||
          normalized['description'] == null) {
        normalized['description'] = '';
      }
    }

    if (table != 'audit_logs') return normalized;

    final entityType = remote['entity_type']?.toString().trim();
    final action = remote['action']?.toString().trim();

    if (!normalized.containsKey('module')) {
      normalized['module'] = _auditModule(entityType, action);
    }
    if (!normalized.containsKey('record_id') && remote.containsKey('entity_id')) {
      normalized['record_id'] = remote['entity_id'];
    }
    if (!normalized.containsKey('details') && remote.containsKey('metadata')) {
      normalized['details'] = remote['metadata'];
    }
    if (!normalized.containsKey('details') && remote.containsKey('reason')) {
      normalized['details'] = remote['reason'];
    }

    return normalized;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _auditModule(String? entityType, String? action) {
    final key = entityType?.toLowerCase().replaceAll('-', '_') ?? '';
    const aliases = <String, String>{
      'user': 'AUTH',
      'auth': 'AUTH',
      'business': 'BUSINESS',
      'business_profile': 'BUSINESS',
      'location': 'BUSINESS',
      'product': 'INVENTORY',
      'category': 'INVENTORY',
      'supplier': 'INVENTORY',
      'stock_movement': 'INVENTORY',
      'inventory_movement': 'INVENTORY',
      'customer': 'CUSTOMERS',
      'sale': 'SALES',
      'sale_item': 'SALES',
      'return': 'POS_RETURN',
      'return_request': 'POS_RETURN',
      'expense': 'FINANCE',
      'expense_category': 'FINANCE',
      'income': 'FINANCE',
      'income_record': 'FINANCE',
      'tax_remittance': 'FINANCE',
      'cash_drawer_shift': 'POS_SHIFT',
      'employee': 'EMPLOYEES',
      'staff': 'EMPLOYEES',
      'audit': 'BACKUP',
    };
    final mapped = aliases[key];
    if (mapped != null) return mapped;
    if (key.isNotEmpty) return key.toUpperCase();
    if (action != null && action.isNotEmpty) return 'SYSTEM';
    return 'SYSTEM';
  }

  Future<void> _insertValues(String table, Map<String, Object?> values) async {
    final columns = values.keys.toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(', ');
    await _db.customStatement(
      'INSERT INTO ${_quoteIdentifier(table)} (${columns.map(_quoteIdentifier).join(', ')}) VALUES ($placeholders)',
      values.values.toList(growable: false),
    );
  }

  String? _remoteKeyForColumn(String localColumn, Map<String, dynamic> remote) {
    if (remote.containsKey(localColumn)) return localColumn;
    if (localColumn.endsWith('_local_id')) {
      final candidate = '${localColumn.substring(0, localColumn.length - 9)}_id';
      if (remote.containsKey(candidate)) return candidate;
    }
    return null;
  }

  Object? _coerce(Object? value, String sqliteType) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is Map || value is List) return jsonEncode(value);
    if (sqliteType.contains('INT')) {
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
        final date = DateTime.tryParse(value);
        if (date != null) return date.millisecondsSinceEpoch;
      }
    }
    if (sqliteType.contains('REAL') || sqliteType.contains('DOUBLE') || sqliteType.contains('FLOAT')) {
      if (value is num) return value.toDouble();
    }
    return value.toString();
  }

  DateTime _dateOrNow(Object? value, DateTime fallback) {
    if (value is String) return DateTime.tryParse(value)?.toLocal() ?? fallback;
    return fallback;
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  String _quoteIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';
}

class CloudRestoreResult {
  const CloudRestoreResult(this.importedCounts, {this.expectedCounts = const {}});

  final Map<String, int> importedCounts;
  final Map<String, int> expectedCounts;

  int get totalRows => importedCounts.values.fold(0, (sum, count) => sum + count);
}

class _StaffRestoreCounts {
  const _StaffRestoreCounts({required this.expected, required this.imported});

  final Map<String, int> expected;
  final Map<String, int> imported;
}

class _TableInfo {
  const _TableInfo(this.columns);

  final List<_ColumnInfo> columns;
  bool has(String name) => columns.any((column) => column.name == name);
}

class _ColumnInfo {
  const _ColumnInfo({required this.name, required this.type, required this.notNull, required this.hasDefault});

  final String name;
  final String type;
  final bool notNull;
  final bool hasDefault;
}