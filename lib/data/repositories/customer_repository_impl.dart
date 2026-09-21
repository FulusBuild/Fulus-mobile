import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'customer_mapper.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<Customer> createCustomer(CustomerDraft draft) async {
    final localId = Ulid().toString();
    final customer = draft.toCustomerEntity(localId: localId);

    await _db.transaction(() async {
      await _db.into(_db.customers).insert(customer.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createCustomer(localId));
    });

    return customer;
  }

  @override
  Stream<List<Customer>> watchCustomers({bool archivedOnly = false}) {
    final query = _db.select(_db.customers)
      ..where((c) => archivedOnly ? c.deletedAt.isNotNull() : c.deletedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Customer?> getCustomerById(String localId) async {
    final row = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<Customer> updateCustomer(String localId, CustomerDraft draft) async {
    final updated = draft.toCustomerEntity(localId: localId);
    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((c) => c.localId.equals(localId))).write(
        CustomersCompanion(
          name: Value(updated.name),
          phone: Value(updated.phone),
          email: Value(updated.email),
          address: Value(updated.address),
          notes: Value(updated.notes),
          creditLimit: Value(updated.creditLimit),
          loyaltyThreshold: Value(updated.loyaltyThreshold),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateCustomer(localId));
    });
    return (await getCustomerById(localId))!;
  }

  @override
  Future<void> archiveCustomer(String localId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((c) => c.localId.equals(localId))).write(
        CustomersCompanion(
          deletedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(now),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateCustomer(localId));
    });
  }

  @override
  Future<void> restoreCustomer(String localId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((c) => c.localId.equals(localId))).write(
        CustomersCompanion(
          deletedAt: const Value(null),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(now),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateCustomer(localId));
    });
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required double outstandingBalance,
    String? duplicateWarning,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final existing = await (_db.select(_db.customers)
          ..where((c) => c.serverId.equals(serverId)))
        .getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();

    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.customers).insert(
              CustomersCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                name: name,
                phone: Value(phone),
                email: Value(email),
                address: Value(address),
                notes: Value(notes),
                outstandingBalance: Value(outstandingBalance),
                createdAt: updatedAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: SyncStatus.settled,
                lastSyncWarning: Value(duplicateWarning),
              ),
            );
      } else {
        await (_db.update(_db.customers)..where((c) => c.localId.equals(localId))).write(
          CustomersCompanion(
            serverId: Value(serverId),
            name: Value(name),
            phone: Value(phone),
            email: Value(email),
            address: Value(address),
            notes: Value(notes),
            outstandingBalance: Value(outstandingBalance),
            lastSyncWarning: Value(duplicateWarning),
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
    final now = DateTime.now();
    await (_db.update(_db.customers)..where((c) => c.serverId.equals(serverId))).write(
      CustomersCompanion(
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
    String? duplicateWarning,
  }) async {
    await (_db.update(_db.customers)..where((c) => c.localId.equals(localId)))
        .write(
      CustomersCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
        lastSyncWarning: Value(duplicateWarning),
      ),
    );
  }
}
