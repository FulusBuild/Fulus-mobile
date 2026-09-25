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

    await _db.transaction(() async {
      await _db.into(_db.suppliers).insert(supplier.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createSupplier(localId));
    });

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
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.suppliers)..where((s) => s.localId.equals(localId))).write(
        SuppliersCompanion(
          name: Value(draft.name),
          phone: Value(draft.phone),
          email: Value(draft.email),
          address: Value(draft.address),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(now),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateSupplier(localId));
    });
    final updated = await getSupplierById(localId);
    if (updated == null) {
      throw ArgumentError.value(localId, 'localId', 'no such supplier');
    }
    return updated;
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? phone,
    String? email,
    String? address,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final existing = await (_db.select(_db.suppliers)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();

    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.suppliers).insert(
              SuppliersCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                name: name,
                phone: Value(phone),
                email: Value(email),
                address: Value(address),
                createdAt: updatedAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.suppliers)..where((s) => s.localId.equals(localId))).write(
          SuppliersCompanion(
            serverId: Value(serverId),
            name: Value(name),
            phone: Value(phone),
            email: Value(email),
            address: Value(address),
            deletedAt: Value(deletedAt),
            syncStatus: const Value(SyncStatus.settled),
            updatedAt: Value(updatedAt),
          ),
        );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.suppliers)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.suppliers)..where((s) => s.localId.equals(row.localId))).write(
      SuppliersCompanion(
        deletedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? operationId,
  }) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (current == null) {
          // A missing operation row means this completion is stale. Never
          // allow an old network response to settle a mutation whose queue
          // identity is no longer present.
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'supplier',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.suppliers)..where((x) => x.localId.equals(localId))).write(
        SuppliersCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }
}
