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
  SyncQueue(this._db);

  final AppDatabase _db;
  Future<void> Function()? _onEnqueued;

  void setOnEnqueued(Future<void> Function() callback) {
    _onEnqueued = callback;
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

  /// Seeds the durable queue with business records that already existed
  /// before cloud backup was connected. Normal repository writes enqueue
  /// themselves, but a business created offline can contain historical rows
  /// that were written before a cloud account existed. Without this pass,
  /// the initial reconciliation would see an empty queue and upload nothing.
  ///
  /// Only entity types with a real sync handler are seeded. Device-only
  /// tables (for example users, permissions, diagnostics, and local stock
  /// level projections) are intentionally not treated as cloud records.
  /// Soft-deleted rows are skipped because they were already deleted locally
  /// before the first cloud connection and must not be recreated remotely.
  Future<void> seedExistingBusinessData() async {
    final tasks = <SyncTask>[];

    Future<void> add(String entityType, Future<List<String>> Function() ids,
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
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForSuppliers() async => (await _db.select(_db.suppliers).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForCustomers() async => (await _db.select(_db.customers).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
        .map((row) => row.localId)
        .toList();
    Future<List<String>> idsForProducts() async => (await _db.select(_db.products).get())
        .where((row) => row.serverId == null && row.deletedAt == null)
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
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForCashDrawerShifts() async =>
        (await _db.select(_db.cashDrawerShifts).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();
    Future<List<String>> idsForCustomerLedger() async =>
        (await _db.select(_db.customerLedgerEntries).get())
            .where((row) => row.serverId == null && row.deletedAt == null)
            .map((row) => row.localId)
            .toList();

    await add('location', idsForLocations, SyncTask.createLocation);
    await add('category', idsForCategories, SyncTask.createCategory);
    await add('supplier', idsForSuppliers, SyncTask.createSupplier);
    await add('customer', idsForCustomers, SyncTask.createCustomer);
    await add('expense_category', idsForExpenseCategories, SyncTask.createExpenseCategory);
    await add('product', idsForProducts, SyncTask.createProduct);
    await add('expense', idsForExpenses, SyncTask.createExpense);
    await add('income_record', idsForIncomeRecords, SyncTask.createIncomeRecord);
    await add('stock_movement', idsForStockMovements, SyncTask.recordStockMovement);
    await add('sale', idsForSales, SyncTask.createSale);
    await add('return', idsForReturns, SyncTask.createReturn);
    await add('cash_drawer_shift', idsForCashDrawerShifts, SyncTask.createCashDrawerShift);
    await add('customer_ledger', idsForCustomerLedger, SyncTask.recordCustomerRepayment);

    final shifts = await _db.select(_db.cashDrawerShifts).get();
    for (final shift in shifts) {
      if (shift.serverId == null || shift.serverId!.isEmpty ||
          shift.deletedAt != null || shift.closedAt == null) {
        continue;
      }
      final existingClose = tasks.any(
        (task) => task.entityType == 'cash_drawer_shift' &&
            task.entityLocalId == shift.localId && task.operation == 'close',
      );
      if (!existingClose) tasks.add(SyncTask.closeCashDrawerShift(shift.localId));
    }

    if (tasks.isEmpty) return;

    final existingRows = await _db.select(_db.syncQueueItems).get();
    final existingKeys = existingRows
        .map((row) => '${row.entityType}|${row.entityLocalId}|${row.operation}')
        .toSet();

    await _db.transaction(() async {
      for (final task in tasks) {
        final key = '${task.entityType}|${task.entityLocalId}|${task.operation}';
        if (!existingKeys.add(key)) continue;
        await _db.into(_db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: Ulid().toString(),
            entityType: task.entityType,
            entityLocalId: task.entityLocalId,
            operation: task.operation,
            priority: task.priority,
            enqueuedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  Future<void> enqueue(SyncTask task) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.syncQueueItems)
            ..where((q) => q.entityType.equals(task.entityType))
            ..where((q) => q.entityLocalId.equals(task.entityLocalId))
            ..where((q) => q.operation.equals(task.operation))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) return;

      await _db.into(_db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: Ulid().toString(),
          entityType: task.entityType,
          entityLocalId: task.entityLocalId,
          operation: task.operation,
          priority: task.priority,
          enqueuedAt: DateTime.now(),
        ),
      );
    });

    final callback = _onEnqueued;
    if (callback != null) unawaited(callback());
  }
}
