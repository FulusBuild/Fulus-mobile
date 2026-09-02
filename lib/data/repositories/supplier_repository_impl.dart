import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'supplier_mapper.dart';

class SupplierRepositoryImpl implements SupplierRepository {
  SupplierRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<Supplier> createSupplier(SupplierDraft draft) async {
    final localId = Ulid().toString();
    final supplier = draft.toSupplierEntity(localId: localId);

    await _db.into(_db.suppliers).insert(supplier.toDriftCompanion());

    await _syncQueue.enqueue(SyncTask.createSupplier(localId));

    return supplier;
  }

  @override
  Stream<List<Supplier>> watchSuppliers() {
    final query = _db.select(_db.suppliers)
      ..where((s) => s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Supplier?> getSupplierById(String localId) async {
    final row = await (_db.select(_db.suppliers)
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<Supplier> updateSupplier(String localId, SupplierDraft draft) async {
    await (_db.update(_db.suppliers)..where((s) => s.localId.equals(localId))).write(
      SuppliersCompanion(
        name: Value(draft.name),
        phone: Value(draft.phone),
        email: Value(draft.email),
        address: Value(draft.address),
        updatedAt: Value(DateTime.now()),
      ),
    );
    final updated = await getSupplierById(localId);
    if (updated == null) {
      throw ArgumentError.value(localId, 'localId', 'no such supplier');
    }
    return updated;
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.suppliers)..where((s) => s.localId.equals(localId)))
        .write(
      SuppliersCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
