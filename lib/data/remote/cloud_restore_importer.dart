import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database/database.dart';

/// Rehydrates portable business data from the server restore snapshot.
///
/// Remote UUIDs are intentionally used as both localId and serverId. The
/// normal pull handlers already use this identity for server-originated rows,
/// which means every foreign key in the snapshot continues to point at the
/// same value after import. Device-only tables are never touched.
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

  // Child tables must be cleared before their parents. Parents are imported
  // first for the same reason: SQLite foreign-key enforcement stays on.
  static const _clearOrder = <String>[
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
  ];

  Future<CloudRestoreResult> importSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final version = snapshot['version'];
    if (version is! num || version.toInt() < 2) {
      throw const FormatException('Unsupported Fulus restore snapshot version.');
    }

    final importedCounts = <String, int>{};

    await _db.transaction(() async {
      await _clearPortableData();

      final tableInfoCache = <String, _TableInfo>{};
      for (final localTable in _importOrder) {
        final remoteKey = _tableMap.entries
            .firstWhere((entry) => entry.value == localTable,
                orElse: () => const MapEntry('', ''))
            .key;
        if (remoteKey.isEmpty) continue;
        final raw = snapshot[remoteKey];
        if (raw is! List || raw.isEmpty) continue;

        final info = tableInfoCache[localTable] ??= await _readTableInfo(localTable);
        if (info.columns.isEmpty) {
          throw StateError('Local restore table "$localTable" does not exist.');
        }

        var count = 0;
        for (final value in raw) {
          if (value is! Map) {
            throw FormatException('$remoteKey contains a non-object row.');
          }
          await _insertRow(
            localTable,
            info,
            Map<String, dynamic>.from(value),
          );
          count++;
        }
        importedCounts[remoteKey] = count;
      }
    });

    return CloudRestoreResult(importedCounts);
  }

  Future<void> _clearPortableData() async {
    for (final table in _clearOrder) {
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
      rows
          .map((row) => _ColumnInfo(
                name: row.read<String>('name'),
                type: row.read<String>('type').toUpperCase(),
                notNull: row.read<int>('notnull') == 1,
                hasDefault: row.data['dflt_value'] != null,
              ))
          .toList(growable: false),
    );
  }

  Future<void> _insertRow(
    String table,
    _TableInfo info,
    Map<String, dynamic> remote,
  ) async {
    final values = <String, Object?>{};

    for (final column in info.columns) {
      final remoteKey = _remoteKeyForColumn(column.name, remote);
      if (remoteKey == null) continue;
      values[column.name] = _coerce(remote[remoteKey], column.type);
    }

    final remoteId = remote['id']?.toString();
    if (remoteId != null && remoteId.isNotEmpty) {
      if (info.has('local_id')) values['local_id'] = remoteId;
      if (info.has('server_id')) values['server_id'] = remoteId;
      if (info.has('id')) values['id'] = remoteId;
    }

    if (info.has('sync_status') && !values.containsKey('sync_status')) {
      values['sync_status'] = 'settled';
    }
    if (info.has('created_at') && !values.containsKey('created_at')) {
      values['created_at'] = DateTime.now().microsecondsSinceEpoch;
    }
    if (info.has('updated_at') && !values.containsKey('updated_at')) {
      values['updated_at'] = values['created_at'] ?? DateTime.now().microsecondsSinceEpoch;
    }

    final missing = info.columns
        .where((column) => column.notNull && !column.hasDefault && !values.containsKey(column.name))
        .map((column) => column.name)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError('Cannot restore $table row: missing required columns ${missing.join(', ')}.');
    }

    if (values.isEmpty) {
      throw StateError('Cannot restore an empty $table row.');
    }

    final columns = values.keys.toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(', ');
    final variables = columns.map((column) => _variable(values[column])).toList(growable: false);
    await _db.customStatement(
      'INSERT OR REPLACE INTO ${_quoteIdentifier(table)} '
      '(${columns.map(_quoteIdentifier).join(', ')}) VALUES ($placeholders)',
      variables: variables,
    );
  }

  String? _remoteKeyForColumn(String localColumn, Map<String, dynamic> remote) {
    if (remote.containsKey(localColumn)) return localColumn;

    // Local foreign keys deliberately say which local identity they refer to
    // (sale_local_id/product_local_id/customer_local_id), while the cloud API
    // uses the conventional sale_id/product_id/customer_id names.
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
        if (date != null) return date.microsecondsSinceEpoch;
      }
    }
    if (sqliteType.contains('REAL') || sqliteType.contains('DOUBLE') || sqliteType.contains('FLOAT')) {
      if (value is num) return value.toDouble();
    }
    return value.toString();
  }

  Variable _variable(Object? value) {
    if (value == null) return Variable<Object?>(null);
    if (value is int) return Variable<int>(value);
    if (value is double) return Variable<double>(value);
    if (value is num) return Variable<double>(value.toDouble());
    return Variable<String>(value.toString());
  }

  String _quoteIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';
}

class CloudRestoreResult {
  const CloudRestoreResult(this.importedCounts);

  final Map<String, int> importedCounts;

  int get totalRows => importedCounts.values.fold(0, (sum, count) => sum + count);
}

class _TableInfo {
  const _TableInfo(this.columns);

  final List<_ColumnInfo> columns;

  bool has(String name) => columns.any((column) => column.name == name);
}

class _ColumnInfo {
  const _ColumnInfo({
    required this.name,
    required this.type,
    required this.notNull,
    required this.hasDefault,
  });

  final String name;
  final String type;
  final bool notNull;
  final bool hasDefault;
}
