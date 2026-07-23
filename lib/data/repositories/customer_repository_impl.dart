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

    await _db.into(_db.customers).insert(customer.toDriftCompanion());

    await _syncQueue.enqueue(SyncTask.createCustomer(localId));

    return customer;
  }

  @override
  Stream<List<Customer>> watchCustomers() {
    final query = _db.select(_db.customers)
      ..where((c) => c.deletedAt.isNull())
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
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.customers)..where((c) => c.localId.equals(localId)))
        .write(
      CustomersCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
