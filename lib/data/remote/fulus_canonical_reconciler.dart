import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database/database.dart';
import 'fulus_sync_api.dart';

/// Applies one server change from canonical cloud state into the local DB.
///
/// The change feed is only a notification. This class fetches the current
/// authoritative entity/aggregate and writes it transactionally before the
/// coordinator is allowed to advance its cursor.
class FulusCanonicalReconciler {
  FulusCanonicalReconciler({
    required AppDatabase db,
    required FulusSyncApi api,
  })  : _db = db,
        _api = api;

  final AppDatabase _db;
  final FulusSyncApi _api;

  static const _entityTables = <String, String>{
    'location': 'locations',
    'product': 'products',
    'category': 'categories',
    'supplier': 'suppliers',
    'customer': 'customers',
    'expense_category': 'expense_categories',
    'expense': 'expenses',
    'income_record': 'income_records',
    'stock_movement': 'stock_movements',
    'customer_ledger': 'customer_ledger_entries',
    'return': 'return_requests',
    'cash_drawer_shift': 'cash_drawer_shifts',
    'sale': 'sales',
  };

  Future<void> reconcile(
    FulusSyncChange change, {
    required String businessId,
    required String deviceClientId,
  }) async {
    if (change.operation != 'upsert' && change.operation != 'delete') {
      throw StateError(
        'Unsupported server sync operation: ${change.operation}',
      );
    }

    final canonical = await _api.fetchCanonicalEntity(
      businessId: businessId,
      entityType: change.entityType,
      entityId: change.entityId,
      deviceClientId: deviceClientId,
    );

    if (canonical.entityType != change.entityType ||
        canonical.entityId != change.entityId) {
      throw StateError('Canonical sync response does not match the change.');
    }

    await _db.transaction(() async {
      final data = canonical.data;
      final operation = data['operation'] as String?;
      if (operation == 'delete') {
        await _deleteCanonical(change.entityType, change.entityId);
        return;
      }
      if (operation != 'upsert') {
        throw StateError(
          'Canonical sync response returned unsupported operation: $operation',
        );
      }

      switch (change.entityType) {
        case 'sale':
          final sale = data['sale'];
          if (sale is! Map) {
            throw StateError('Canonical sale response has no sale row.');
          }
          await _upsertRow('sales', Map<String, dynamic>.from(sale));
          await _replaceChildren(
            table: 'sale_items',
            foreignKeyColumn: 'sale_local_id',
            foreignKeyRemoteId: change.entityId,
            rows: _maps(data['sale_items']),
          );
          await _replaceChildren(
            table: 'sale_payments',
            foreignKeyColumn: 'sale_local_id',
            foreignKeyRemoteId: change.entityId,
            rows: _maps(data['sale_payments']),
          );
          break;
        case 'product':
          final product = data['product'];
          if (product is! Map) {
            throw StateError('Canonical product response has no product row.');
          }
          await _upsertRow('products', Map<String, dynamic>.from(product));
          await _replaceChildren(
            table: 'product_stock_levels',
            foreignKeyColumn: 'product_local_id',
            foreignKeyRemoteId: change.entityId,
            rows: _maps(data['stock_levels']),
          );
          break;
        case 'return':
          final row = data['row'];
          if (row is! Map) {
            throw StateError('Canonical return response has no row.');
          }
          await _upsertRow('return_requests', Map<String, dynamic>.from(row));
          await _replaceChildren(
            table: 'return_items',
            foreignKeyColumn: 'return_request_local_id',
            foreignKeyRemoteId: change.entityId,
            rows: _maps(data['return_items']),
          );
          break;
        default:
          final table = _entityTables[change.entityType];
          if (table == null) {
            throw StateError(
              'Unsupported canonical sync entity: ${change.entityType}',
            );
          }
          final row = data['row'];
          if (row is! Map) {
            throw StateError(
              'Canonical ${change.entityType} response has no row.',
            );
          }
          await _upsertRow(table, Map<String, dynamic>.from(row));
      }
    });
  }

  Future<void> _deleteCanonical(String entityType, String serverId) async {
    switch (entityType) {
      case 'sale':
        final localId = await _localIdForServerId('sales', serverId);
        if (localId != null) {
          await _db.customStatement(
            'DELETE FROM "sale_payments" WHERE "sale_local_id" = ?',
            [localId],
          );
          await _db.customStatement(
            'DELETE FROM "sale_items" WHERE "sale_local_id" = ?',
            [localId],
          );
        }
        await _deleteByServerId('sales', serverId);
        return;
      case 'product':
        final localId = await _localIdForServerId('products', serverId);
        if (localId != null) {
          await _db.customStatement(
            'DELETE FROM "product_stock_levels" WHERE "product_local_id" = ?',
            [localId],
          );
        }
        await _deleteByServerId('products', serverId);
        return;
      case 'return':
        final localId = await _localIdForServerId('return_requests', serverId);
        if (localId != null) {
          await _db.customStatement(
            'DELETE FROM "return_items" WHERE "return_request_local_id" = ?',
            [localId],
          );
        }
        await _deleteByServerId('return_requests', serverId);
        return;
      default:
        final table = _entityTables[entityType];
        if (table == null) {
          throw StateError('Unsupported canonical sync entity: $entityType');
        }
        await _deleteByServerId(table, serverId);
    }
  }

  Future<void> _deleteByServerId(String table, String serverId) async {
    final info = await _readTableInfo(table);
    if (info.has('server_id')) {
      await _db.customStatement(
        'DELETE FROM ${_quote(table)} WHERE "server_id" = ?',
        [serverId],
      );
    } else if (info.has('local_id')) {
      await _db.customStatement(
        'DELETE FROM ${_quote(table)} WHERE "local_id" = ?',
        [serverId],
      );
    } else if (info.has('id')) {
      await _db.customStatement(
        'DELETE FROM ${_quote(table)} WHERE "id" = ?',
        [serverId],
      );
    } else {
      throw StateError('Cannot delete canonical $table row: no key column.');
    }
  }

  Future<void> _upsertRow(
    String table,
    Map<String, dynamic> remote,
  ) async {
    final info = await _readTableInfo(table);
    final values = <String, Object?>{};
    final remoteId = remote['id']?.toString();
    String? existingLocalId;

    if (remoteId != null && remoteId.isNotEmpty && info.has('server_id')) {
      final existing = await _db.customSelect(
        'SELECT "local_id" FROM ${_quote(table)} WHERE "server_id" = ? LIMIT 1',
        variables: [Variable.withString(remoteId)],
      ).getSingleOrNull();
      existingLocalId = existing?.read<String>('local_id');
    }

    for (final column in info.columns) {
      final remoteKey = _remoteKeyForColumn(column.name, remote);
      if (remoteKey == null) continue;
      var value = remote[remoteKey];
      if (column.name.endsWith('_local_id')) {
        value = await _resolveLocalForeignKey(column.name, value);
      }
      values[column.name] = _coerce(value, column.type);
    }

    if (remoteId != null && remoteId.isNotEmpty) {
      if (info.has('local_id')) values['local_id'] = existingLocalId ?? remoteId;
      if (info.has('server_id')) values['server_id'] = remoteId;
      if (info.has('id')) values['id'] = remoteId;
    }
    if (info.has('sync_status')) values['sync_status'] = 'settled';
    if (info.has('created_at') && !values.containsKey('created_at')) {
      values['created_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (info.has('updated_at') && !values.containsKey('updated_at')) {
      values['updated_at'] = values['created_at'] ?? DateTime.now().millisecondsSinceEpoch;
    }

    final missing = info.columns
        .where(
          (column) =>
              column.notNull &&
              !column.hasDefault &&
              !values.containsKey(column.name),
        )
        .map((column) => column.name)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Cannot reconcile $table: missing required columns ${missing.join(', ')}.',
      );
    }
    if (values.isEmpty) {
      throw StateError('Cannot reconcile an empty $table row.');
    }

    final columns = values.keys.toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(', ');
    final quotedColumns = columns.map(_quote).join(', ');
    final updateColumns = columns
        .where(
          (column) =>
              column != 'local_id' &&
              !(table == 'product_stock_levels' &&
                  (column == 'product_local_id' ||
                      column == 'location_local_id')),
        )
        .map((column) => '${_quote(column)} = excluded.${_quote(column)}')
        .join(', ');

    final conflict = info.has('local_id')
        ? ' ON CONFLICT("local_id")'
        : ' ON CONFLICT';
    final statement = updateColumns.isEmpty
        ? 'INSERT INTO ${_quote(table)} ($quotedColumns) VALUES ($placeholders)$conflict DO NOTHING'
        : 'INSERT INTO ${_quote(table)} ($quotedColumns) VALUES ($placeholders)$conflict DO UPDATE SET $updateColumns';
    await _db.customStatement(statement, values.values.toList(growable: false));
  }

  Future<void> _replaceChildren({
    required String table,
    required String foreignKeyColumn,
    required String foreignKeyRemoteId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final parentPrefix = foreignKeyColumn.substring(
      0,
      foreignKeyColumn.length - '_local_id'.length,
    );
    final parentTable = <String, String>{
      'sale': 'sales',
      'product': 'products',
      'return_request': 'return_requests',
    }[parentPrefix];
    if (parentTable == null) {
      throw StateError('Unsupported canonical child parent: $parentPrefix');
    }
    final parentLocalId = await _localIdForServerId(
      parentTable,
      foreignKeyRemoteId,
    );
    if (parentLocalId == null) {
      throw StateError(
        'Cannot reconcile $table: parent $foreignKeyRemoteId is not present locally.',
      );
    }

    await _db.customStatement(
      'DELETE FROM ${_quote(table)} WHERE ${_quote(foreignKeyColumn)} = ?',
      [parentLocalId],
    );
    for (final row in rows) {
      await _upsertRow(table, {
        ...row,
        '${parentPrefix}_id': foreignKeyRemoteId,
      });
    }
  }

  Future<String?> _localIdForServerId(String table, String serverId) async {
    final info = await _readTableInfo(table);
    if (info.has('server_id')) {
      final row = await _db.customSelect(
        'SELECT "local_id" FROM ${_quote(table)} WHERE "server_id" = ? LIMIT 1',
        variables: [Variable.withString(serverId)],
      ).getSingleOrNull();
      if (row != null) return row.read<String>('local_id');
    }
    if (info.has('local_id')) {
      final row = await _db.customSelect(
        'SELECT "local_id" FROM ${_quote(table)} WHERE "local_id" = ? LIMIT 1',
        variables: [Variable.withString(serverId)],
      ).getSingleOrNull();
      return row?.read<String>('local_id');
    }
    return null;
  }

  Future<String?> _resolveLocalForeignKey(
    String localColumn,
    Object? remoteValue,
  ) async {
    if (remoteValue == null) return null;
    final serverId = remoteValue.toString();
    final prefix = localColumn.substring(
      0,
      localColumn.length - '_local_id'.length,
    );
    final table = <String, String>{
      'sale': 'sales',
      'product': 'products',
      'customer': 'customers',
      'location': 'locations',
      'supplier': 'suppliers',
      'category': 'categories',
      'return_request': 'return_requests',
    }[prefix];
    if (table == null) return serverId;
    final localId = await _localIdForServerId(table, serverId);
    if (localId == null) {
      throw StateError(
        'Canonical dependency $prefix $serverId is not reconciled on this device yet.',
      );
    }
    return localId;
  }

  Future<_TableInfo> _readTableInfo(String table) async {
    final rows = await _db.customSelect(
      'PRAGMA table_info(${_quote(table)})',
    ).get();
    return _TableInfo(
      rows
          .map(
            (row) => _ColumnInfo(
              name: row.read<String>('name'),
              type: row.read<String>('type').toUpperCase(),
              notNull: row.read<int>('notnull') == 1,
              hasDefault: row.data['dflt_value'] != null,
            ),
          )
          .toList(growable: false),
    );
  }

  String? _remoteKeyForColumn(
    String localColumn,
    Map<String, dynamic> remote,
  ) {
    if (remote.containsKey(localColumn)) return localColumn;
    if (localColumn.endsWith('_local_id')) {
      final candidate =
          '${localColumn.substring(0, localColumn.length - '_local_id'.length)}_id';
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
    if (sqliteType.contains('REAL') ||
        sqliteType.contains('DOUBLE') ||
        sqliteType.contains('FLOAT')) {
      if (value is num) return value.toDouble();
    }
    return value.toString();
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';
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
