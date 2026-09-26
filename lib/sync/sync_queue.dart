import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../data/local/database/database.dart';

/// Sync lanes are ordered around dependencies as well as business urgency.
/// Reference data must reach the server before a sale can reference it by
/// server ID, so catalog/customer/location writes share the first lane.
abstract final class SyncPriority {
  static const salesAndPayments = 1;
  static const stockAndCustomerWrites = 0;
  static const photosAndBulkImport = 2;
}

class SyncTask {
  const SyncTask({
    required this.entityType,
    required this.entityLocalId,
    required this.operation,
    required this.priority,
  });

  factory SyncTask.createSale(String localId) => SyncTask(
        entityType: 'sale', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.salesAndPayments,
      );
  factory SyncTask.updateCustomer(String localId) => SyncTask(
        entityType: 'customer', entityLocalId: localId, operation: 'update',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createCustomer(String localId) => SyncTask(
        entityType: 'customer', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.updateExpense(String localId) => SyncTask(
        entityType: 'expense', entityLocalId: localId, operation: 'update',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createExpense(String localId) => SyncTask(
        entityType: 'expense', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createIncomeRecord(String localId) => SyncTask(
        entityType: 'income_record', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.updateCategory(String localId) => SyncTask(
        entityType: 'category', entityLocalId: localId, operation: 'update',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createCategory(String localId) => SyncTask(
        entityType: 'category', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createSupplier(String localId) => SyncTask(
        entityType: 'supplier', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.updateSupplier(String localId) => SyncTask(
        entityType: 'supplier', entityLocalId: localId, operation: 'update',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createLocation(String localId) => SyncTask(
        entityType: 'location', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createReturn(String localId) => SyncTask(
        entityType: 'return', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.salesAndPayments,
      );
  factory SyncTask.createExpenseCategory(String localId) => SyncTask(
        entityType: 'expense_category', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createCashDrawerShift(String localId) => SyncTask(
        entityType: 'cash_drawer_shift', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.salesAndPayments,
      );
  factory SyncTask.closeCashDrawerShift(String localId) => SyncTask(
        entityType: 'cash_drawer_shift', entityLocalId: localId, operation: 'close',
        priority: SyncPriority.salesAndPayments,
      );
  factory SyncTask.recordCustomerRepayment(String localId) => SyncTask(
        entityType: 'customer_ledger', entityLocalId: localId, operation: 'repayment',
        priority: SyncPriority.salesAndPayments,
      );
  factory SyncTask.recordStockMovement(String localId) => SyncTask(
        entityType: 'stock_movement', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.createProduct(String localId) => SyncTask(
        entityType: 'product', entityLocalId: localId, operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
      );
  factory SyncTask.updateProduct(String localId) => SyncTask(
        entityType: 'product', entityLocalId: localId, operation: 'update',
        priority: SyncPriority.stockAndCustomerWrites,
      );

  final String entityType;
  final String entityLocalId;
  final String operation;
  final int priority;
}

class SyncQueue {
  SyncQueue(this._db, {int? Function()? baseCursorProvider})
      : _baseCursorProvider = baseCursorProvider;

  final AppDatabase _db;
  final int? Function()? _baseCursorProvider;
  Future<void> Function()? _onEnqueued;
  bool _businessSwitchBarrier = false;

  void setOnEnqueued(Future<void> Function() callback) {
    _onEnqueued = callback;
  }

  /// Fences durable local mutations while a business context switch is being
  /// coordinated. Repositories enqueue inside their business write
  /// transaction, so rejecting here rolls that transaction back instead of
  /// allowing a mutation to land between the final pending-work check and
  /// the context change.
  Future<void> beginBusinessSwitchBarrier() async {
    if (_businessSwitchBarrier) {
      throw StateError('Another business switch is already in progress.');
    }
    _businessSwitchBarrier = true;
  }

  void endBusinessSwitchBarrier() {
    _businessSwitchBarrier = false;
  }

  /// Repairs queue rows written by older builds where sales were processed
  /// ahead of their catalog/customer/location dependencies. Safe to run on
  /// every startup and intentionally only changes ordering metadata.
  Future<void> normalizeDependencyPriorities() async {
    await _db.transaction(() async {
      const dependencyTypes = [
        'customer', 'category', 'supplier', 'location', 'expense_category',
        'product', 'stock_movement', 'expense', 'income_record',
      ];
      await (_db.update(_db.syncQueueItems)
            ..where((q) => q.entityType.isIn(dependencyTypes)))
          .write(const SyncQueueItemsCompanion(priority: Value(0)));

      const financialTypes = ['sale', 'return', 'cash_drawer_shift', 'customer_ledger'];
      await (_db.update(_db.syncQueueItems)
            ..where((q) => q.entityType.isIn(financialTypes)))
          .write(const SyncQueueItemsCompanion(priority: Value(1)));
    });
  }

  /// Returns whether a newer durable queue mutation exists for the same
  /// entity, excluding [operationId]. Call this from a repository transaction
  /// so the queue check and the final sync-state write share the same SQLite
  /// writer transaction. This closes the stale-handler completion race: if a
  /// newer local mutation already committed, an older network response may
  /// still establish the server identity but must not settle the newer state.
  Future<bool> hasNewerQueueMutation({
    required String entityType,
    required String entityLocalId,
    required String operationId,
    required DateTime enqueuedAt,
  }) async {
    final rows = await (_db.select(_db.syncQueueItems)
          ..where((q) => q.entityType.equals(entityType))
          ..where((q) => q.entityLocalId.equals(entityLocalId))
          ..where((q) => q.id.isNotIn([operationId]))
          ..where((q) => q.enqueuedAt.isBiggerOrEqualValue(enqueuedAt)))
        .get();
    return rows.isNotEmpty;
  }

  /// Seeds the durable queue with business records that already existed
  /// before cloud backup was connected. Normal repository writes enqueue
  /// themselves, but a business created offline can contain historical rows
  /// that were written before a cloud account existed. Without this pass,
  /// the initial reconciliation would see an empty queue and upload nothing.
  ///
  /// Only entity types with a real sync handler are seeded. Device-only
  /// tables (for example users, permissions, diagnostics, and local stock
  /// level projections) are intentionally not treated as cloud records.
  /// Pre-cloud archived rows are intentionally seeded too. Product/category/
  /// supplier/customer handlers complete those lifecycles by creating the
  /// server row first and then applying the archive/delete operation with a
  /// second stable operation ID. Skipping such rows would permanently lose
  /// valid local history at first cloud connection.
  Future<void> seedExistingBusinessData() async {
    final tasks = <SyncTask>[];

    Future<void> add(Future<List<String>> Function() ids,
        SyncTask Function(String) create) async {
      final localIds = await ids();
      for (final localId in localIds) {
        tasks.add(create(localId));
      }
    }

    Future<List<String>> idsForLocations() async => (await _db.select(_db.locations).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForCategories() async => (await _db.select(_db.categories).get())
        .where((row) => row.serverId == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForSuppliers() async => (await _db.select(_db.suppliers).get())
        .where((row) => row.serverId == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForCustomers() async => (await _db.select(_db.customers).get())
        .where((row) => row.serverId == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForProducts() async => (await _db.select(_db.products).get())
        .where((row) => row.serverId == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForExpenseCategories() async =>
        (await _db.select(_db.expenseCategories).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForExpenses() async => (await _db.select(_db.expenses).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForIncomeRecords() async =>
        (await _db.select(_db.incomeRecords).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForStockMovements() async =>
        (await _db.select(_db.stockMovements).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForSales() async => (await _db.select(_db.sales).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForReturns() async =>
        (await _db.select(_db.returnRequests).get())
            .where((row) =>
                row.serverId == null &&
                row.deletedAt == null &&
                row.status == 'completed')
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForCashDrawerShifts() async =>
        (await _db.select(_db.cashDrawerShifts).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForCustomerLedger() async =>
        (await _db.select(_db.customerLedgerEntries).get())
            .where((row) =>
                row.serverId == null &&
                row.deletedAt == null &&
                row.entryType == 'repayment')
            .map((row) => row.localId)
            .toList();

    await add(idsForLocations, SyncTask.createLocation);
    await add(idsForCategories, SyncTask.createCategory);
    await add(idsForSuppliers, SyncTask.createSupplier);
    await add(idsForCustomers, SyncTask.createCustomer);
    await add(idsForExpenseCategories, SyncTask.createExpenseCategory);
    await add(idsForProducts, SyncTask.createProduct);
    await add(idsForExpenses, SyncTask.createExpense);
    await add(idsForIncomeRecords, SyncTask.createIncomeRecord);
    await add(idsForStockMovements, SyncTask.recordStockMovement);
    await add(idsForSales, SyncTask.createSale);
    await add(idsForReturns, SyncTask.createReturn);
    await add(idsForCashDrawerShifts, SyncTask.createCashDrawerShift);
    await add(idsForCustomerLedger, SyncTask.recordCustomerRepayment);

    // Closed shifts need both lifecycle operations. The create task is added
    // above first; the close task follows it so the queue's stable enqueue
    // ordering lets the handler obtain the server shift ID before closing it.
    final shifts = await _db.select(_db.cashDrawerShifts).get();
    for (final shift in shifts) {
      if (shift.deletedAt != null || shift.closedAt == null ||
          shift.serverId != null && shift.serverId!.isNotEmpty) {
        continue;
      }
      tasks.add(SyncTask.closeCashDrawerShift(shift.localId));
    }

    if (tasks.isEmpty) return;

    // Re-check existing queue rows inside the same transaction that inserts
    // seed rows. The first-time cloud-connection flow can run while a local
    // mutation is being committed; taking the snapshot outside this
    // transaction could race that enqueue and create two queue rows with
    // different operation IDs for the same business mutation. For catalog
    // creates in particular, that would defeat server idempotency and could
    // duplicate a cloud record.
    await _db.transaction(() async {
      final existingRows = await _db.select(_db.syncQueueItems).get();
      final existingKeys = existingRows
          .map((row) => '${row.entityType}|${row.entityLocalId}|${row.operation}')
          .toSet();

      for (final task in tasks) {
        final key = '${task.entityType}|${task.entityLocalId}|${task.operation}';
        if (!existingKeys.add(key)) continue;

        // The task list was collected before this transaction started. A
        // concurrent sync cycle can finish a create in that window, assign a
        // serverId, and remove its queue row. Re-check the current local row
        // before seeding so that stale pre-cloud snapshots cannot recreate a
        // fresh operation after the original queue row has already settled.
        if (task.operation == 'create' &&
            await _hasServerIdentity(task.entityType, task.entityLocalId)) {
          continue;
        }

        await _db.into(_db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: Ulid().toString(),
            entityType: task.entityType,
            entityLocalId: task.entityLocalId,
            operation: task.operation,
            priority: task.priority,
            enqueuedAt: DateTime.now(),
            baseCursor: Value(_baseCursorProvider?.call()),
          ),
        );
      }
    });
  }

  Future<bool> _hasServerIdentity(String entityType, String localId) async {
    switch (entityType) {
      case 'location':
        return (await (_db.select(_db.locations)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'category':
        return (await (_db.select(_db.categories)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'supplier':
        return (await (_db.select(_db.suppliers)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'customer':
        return (await (_db.select(_db.customers)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'expense_category':
        return (await (_db.select(_db.expenseCategories)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'product':
        return (await (_db.select(_db.products)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'expense':
        return (await (_db.select(_db.expenses)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'income_record':
        return (await (_db.select(_db.incomeRecords)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'stock_movement':
        return (await (_db.select(_db.stockMovements)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'sale':
        return (await (_db.select(_db.sales)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'return':
        return (await (_db.select(_db.returnRequests)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      case 'cash_drawer_shift':
        return (await (_db.select(_db.cashDrawerShifts)
                  ..where((r) => r.localId.equals(localId)))
              .getSingleOrNull())
            ?.serverId
            ?.isNotEmpty ==
            true;
      default:
        return false;
    }
  }

  Future<bool> hasPendingItems() async {
    final row = await (_db.select(_db.syncQueueItems)..limit(1)).getSingleOrNull();
    return row != null;
  }

  Future<void> enqueue(SyncTask task) async {
    if (_businessSwitchBarrier) {
      throw StateError('Business context is switching; local mutation was rejected before durable enqueue.');
    }
    await _db.transaction(() async {
      if (_businessSwitchBarrier) {
        throw StateError('Business context is switching; local mutation was rejected before durable enqueue.');
      }
      final existing = await (_db.select(_db.syncQueueItems)
            ..where((q) => q.entityType.equals(task.entityType))
            ..where((q) => q.entityLocalId.equals(task.entityLocalId))
            ..where((q) => q.operation.equals(task.operation))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        final blocked = (existing.lastError ?? '').startsWith('[BLOCKED]') ||
            (existing.lastError ?? '').startsWith('[CONFLICT]');

        // UPDATE operations need a fresh durable queue identity for each
        // local mutation. The handler reads the mutable local row when it
        // starts. If the row is edited while an older update is in flight,
        // coalescing into the same queue row lets the older completion remove
        // the only queue entry and mark the newer local state settled.
        // Replacing the row leaves the newer mutation queued even if the old
        // handler finishes after the replacement. Offline repeated edits still
        // coalesce to one row because the previous update is replaced before
        // the next drain.
        if (task.operation == 'update' && !blocked) {
          await (_db.delete(_db.syncQueueItems)
                ..where((q) => q.id.equals(existing.id)))
              .go();
        } else if (!blocked) {
          return;
        } else {
          // A newer local mutation must be able to supersede a permanently
          // parked mutation for the same entity/operation.
          await (_db.delete(_db.syncQueueItems)
                ..where((q) => q.id.equals(existing.id)))
              .go();
          await (_db.update(_db.syncConflictRecords)
                ..where((c) => c.operationId.equals(existing.id))
                ..where((c) => c.resolvedAt.isNull()))
              .write(
            SyncConflictRecordsCompanion(
              resolvedAt: Value(DateTime.now()),
              resolution: const Value('superseded_by_newer_local_mutation'),
            ),
          );
        }
      }

      await _db.into(_db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: Ulid().toString(),
          entityType: task.entityType,
          entityLocalId: task.entityLocalId,
          operation: task.operation,
          priority: task.priority,
          enqueuedAt: DateTime.now(),
          baseCursor: Value(_baseCursorProvider?.call()),
        ),
      );
    });

    final callback = _onEnqueued;
    if (callback != null) {
      // Repository mutations may enqueue from inside their outer Drift
      // transaction. Run the trigger only on the next event-loop turn and in
      // the root zone, after that outer transaction has committed. This keeps
      // the outbox write atomic without allowing SyncEngine to query a closed
      // transaction context.
      Zone.root.run(() {
        Timer.run(() => unawaited(callback()));
      });
    }
  }

  /// Returns whether an outbound mutation is still queued for the canonical
  /// server entity represented by [entityType] and [serverId]. Pull must not
  /// overwrite an optimistic local row while its mutation is waiting to be
  /// sent or retried.
  Future<bool> hasPendingMutationForServerEntity({
    required String entityType,
    required String serverId,
  }) async {
    String? localId;
    switch (entityType) {
      case 'sale':
        localId = (await (_db.select(_db.sales)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'customer':
        localId = (await (_db.select(_db.customers)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'customer_ledger':
        localId = (await (_db.select(_db.customerLedgerEntries)
                  ..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'category':
        localId = (await (_db.select(_db.categories)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'supplier':
        localId = (await (_db.select(_db.suppliers)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'location':
        localId = (await (_db.select(_db.locations)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'return':
        localId = (await (_db.select(_db.returnRequests)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'expense_category':
        localId = (await (_db.select(_db.expenseCategories)
                  ..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'cash_drawer_shift':
        localId = (await (_db.select(_db.cashDrawerShifts)
                  ..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'expense':
        localId = (await (_db.select(_db.expenses)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'income_record':
        localId = (await (_db.select(_db.incomeRecords)
                  ..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'stock_movement':
        localId = (await (_db.select(_db.stockMovements)
                  ..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      case 'product':
        localId = (await (_db.select(_db.products)..where((r) => r.serverId.equals(serverId)))
              .getSingleOrNull())
            ?.localId;
        break;
      default:
        return false;
    }
    if (localId == null) return false;
    final queued = await (_db.select(_db.syncQueueItems)
          ..where((q) => q.entityType.equals(entityType))
          ..where((q) => q.entityLocalId.equals(localId!))
          ..limit(1))
        .getSingleOrNull();
    return queued != null;
  }

}