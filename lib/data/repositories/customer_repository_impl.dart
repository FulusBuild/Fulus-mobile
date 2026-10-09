import 'package:drift/drift.dart';
import '../../core/money/money.dart';
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
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    if (session != null && session.activeLocationId == null) {
      throw StateError('Select an active location before creating a customer.');
    }
    if (session?.activeLocationId != null &&
        draft.locationId != null &&
        draft.locationId != session!.activeLocationId) {
      throw StateError('Customers can only be created in the active location.');
    }
    final customer = draft.toCustomerEntity(
      localId: localId,
      locationIdOverride: session?.activeLocationId ?? draft.locationId,
    );
    if (session != null && customer.locationId == null) {
      throw StateError('Customer ownership requires an active location.');
    }

    await _db.transaction(() async {
      await _db.into(_db.customers).insert(customer.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createCustomer(localId));
    });

    return customer;
  }

  @override
  Stream<List<Customer>> watchCustomers({bool archivedOnly = false}) {
    final query = _db.select(_db.customers).join([
      leftOuterJoin(_db.sessions, _db.sessions.id.equals('current')),
    ])
      ..where(
        _db.sessions.id.isNull() |
            _db.customers.locationId.equalsExp(_db.sessions.activeLocationId),
      )
      ..where(
        archivedOnly
            ? _db.customers.deletedAt.isNotNull()
            : _db.customers.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.asc(_db.customers.name)]);
    return query.watch().map(
          (rows) => rows
              .map((row) => row.readTable(_db.customers).toDomain())
              .toList(),
        );
  }

  @override
  Future<Customer?> getCustomerById(
    String localId, {
    bool forSync = false,
  }) async {
    final row = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    if (row == null) return null;
    if (!forSync) {
      final session = await (_db.select(_db.sessions)
            ..where((session) => session.id.equals('current')))
          .getSingleOrNull();
      if (session != null &&
          (session.activeLocationId == null ||
              row.locationId != session.activeLocationId)) {
        return null;
      }
    }
    return row.toDomain();
  }

  @override
  Future<Customer> updateCustomer(String localId, CustomerDraft draft) async {
    final existing = await getCustomerById(localId);
    if (existing == null) {
      throw StateError('Customer $localId is outside the active location or does not exist.');
    }
    final updated = draft.toCustomerEntity(
      localId: localId,
      locationIdOverride: existing.locationId,
    );
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
    if (await getCustomerById(localId) == null) {
      throw StateError('Customer $localId is outside the active location or does not exist.');
    }
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
    if (await getCustomerById(localId) == null) {
      throw StateError('Customer $localId is outside the active location or does not exist.');
    }
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
    required Money outstandingBalance,
    String? duplicateWarning,
    String? locationId,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final existing = await (_db.select(_db.customers)
          ..where((c) => c.serverId.equals(serverId)))
        .getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();
    final effectiveLocationId =
        await _resolveLocationLocalId(locationId) ?? existing?.locationId;

    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.customers).insert(
              CustomersCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                locationId: Value(effectiveLocationId),
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
            locationId: Value(effectiveLocationId),
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

  Future<String?> _resolveLocationLocalId(String? id) async {
    if (id == null || id.isEmpty) return null;
    final local = await (_db.select(_db.locations)
          ..where((location) => location.localId.equals(id)))
        .getSingleOrNull();
    if (local != null) return local.localId;
    final server = await (_db.select(_db.locations)
          ..where((location) => location.serverId.equals(id)))
        .getSingleOrNull();
    return server?.localId;
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
            entityType: 'customer',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.customers)..where((x) => x.localId.equals(localId))).write(
        CustomersCompanion(
          serverId: Value(serverId),
          lastSyncWarning: Value(duplicateWarning),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }
}
