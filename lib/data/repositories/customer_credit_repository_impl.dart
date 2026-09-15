import '../../sync/sync_queue.dart';

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/customer_credit_engine.dart' as engine;
import '../../domain/entities/customer_ledger_entry.dart';
import '../../domain/repositories/customer_credit_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'customer_ledger_mapper.dart';

class CustomerCreditRepositoryImpl implements CustomerCreditRepository {
  CustomerCreditRepositoryImpl({required AppDatabase db, SyncQueue? syncQueue})
      : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue? _syncQueue;

  Future<CustomerRow> _requireCustomer(String localId) async {
    final row = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(localId) & c.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(localId, 'customerLocalId', 'no such customer');
    }
    return row;
  }

  @override
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final now = DateTime.now();
      final newBalance = customer.outstandingBalance + amount;

      await (_db.update(_db.customers)
            ..where((c) => c.localId.equals(customerLocalId)))
          .write(
        CustomersCompanion(
          outstandingBalance: Value(newBalance),
          updatedAt: Value(now),
        ),
      );

      final entry = CustomerLedgerEntry(
        localId: Ulid().toString(),
        customerLocalId: customerLocalId,
        entryType: CustomerLedgerEntryType.creditSale,
        amount: amount,
        saleLocalId: saleLocalId,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.customerLedgerEntries).insert(
            entry.toDriftCompanion(syncStatus: SyncStatus.settled),
          );
      return entry;
    });
  }

  @override
  Future<
      ({
        CustomerLedgerEntry entry,
        double newBalance,
        double excessAmount,
      })> recordRepayment({
    required String customerLocalId,
    required double amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    final result = await _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final effect = engine.computeRepaymentEffect(
        currentBalance: customer.outstandingBalance,
        repaymentAmount: amount,
      );
      final now = DateTime.now();

      await (_db.update(_db.customers)
            ..where((c) => c.localId.equals(customerLocalId)))
          .write(
        CustomersCompanion(
          outstandingBalance: Value(effect.newBalance),
          updatedAt: Value(now),
        ),
      );

      final entry = CustomerLedgerEntry(
        localId: Ulid().toString(),
        customerLocalId: customerLocalId,
        entryType: CustomerLedgerEntryType.repayment,
        amount: amount,
        paymentMethod: paymentMethod,
        note: note,
        saleLocalId: saleLocalId,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.customerLedgerEntries).insert(
            entry.toDriftCompanion(syncStatus: SyncStatus.pending),
          );

      return (
        entry: entry,
        newBalance: effect.newBalance,
        excessAmount: effect.excessAmount,
      );
    });

    final syncQueue = _syncQueue;
    if (syncQueue != null) {
      await syncQueue.enqueue(SyncTask.recordCustomerRepayment(result.entry.localId));
    }

    return result;
  }

  @override
  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final effect = engine.computeRepaymentEffect(
        currentBalance: customer.outstandingBalance,
        repaymentAmount: amount,
      );
      final now = DateTime.now();

      await (_db.update(_db.customers)
            ..where((c) => c.localId.equals(customerLocalId)))
          .write(
        CustomersCompanion(
          outstandingBalance: Value(effect.newBalance),
          updatedAt: Value(now),
        ),
      );

      final entry = CustomerLedgerEntry(
        localId: Ulid().toString(),
        customerLocalId: customerLocalId,
        entryType: CustomerLedgerEntryType.refundAdjustment,
        amount: amount,
        saleLocalId: saleLocalId,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.customerLedgerEntries).insert(
            entry.toDriftCompanion(syncStatus: SyncStatus.settled),
          );
      return entry;
    });
  }

  @override
  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId) {
    final query = _db.select(_db.customerLedgerEntries)
      ..where((e) => e.customerLocalId.equals(customerLocalId))
      ..orderBy([
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.desc(e.localId),
      ]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    final rows = await (_db.select(_db.customerLedgerEntries)
          ..where(
            (e) =>
                e.entryType.equals('repayment') &
                e.createdAt.isBiggerOrEqualValue(startOfDay) &
                e.createdAt.isSmallerThanValue(endExclusive),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }
}
