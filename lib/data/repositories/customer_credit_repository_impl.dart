import '../../sync/sync_queue.dart';
import '../../core/money/money.dart';

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
    final session = await (_db.select(_db.sessions)
          ..where((session) => session.id.equals('current')))
        .getSingleOrNull();
    if (session == null ||
        session.activeLocationId == null ||
        row.locationId != session.activeLocationId) {
      throw StateError('Customer credit operations require the active owner location.');
    }
    return row;
  }

  @override
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be > 0');
    return _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final now = DateTime.now();
      await (_db.update(_db.customers)..where((c) => c.localId.equals(customerLocalId))).write(
        CustomersCompanion(outstandingBalance: Value(customer.outstandingBalance + amount), updatedAt: Value(now)),
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
      await _db.into(_db.customerLedgerEntries).insert(entry.toDriftCompanion(syncStatus: SyncStatus.settled));
      return entry;
    });
  }

  @override
  Future<({CustomerLedgerEntry entry, Money newBalance, Money excessAmount})> recordRepayment({
    required String customerLocalId,
    required Money amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be > 0');
    return _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final effect = engine.computeRepaymentEffect(currentBalance: customer.outstandingBalance, repaymentAmount: amount);
      final now = DateTime.now();
      await (_db.update(_db.customers)..where((c) => c.localId.equals(customerLocalId))).write(
        CustomersCompanion(outstandingBalance: Value(effect.newBalance), updatedAt: Value(now)),
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
      await _db.into(_db.customerLedgerEntries).insert(entry.toDriftCompanion(syncStatus: SyncStatus.pending));
      final syncQueue = _syncQueue;
      if (syncQueue != null) {
        // The durable outbox row must commit with the balance and ledger entry.
        // SyncQueue defers its trigger until after the surrounding transaction commits.
        await syncQueue.enqueue(SyncTask.recordCustomerRepayment(entry.localId));
      }
      return (entry: entry, newBalance: effect.newBalance, excessAmount: effect.excessAmount);
    });
  }

  @override
  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be > 0');
    return _db.transaction(() async {
      final customer = await _requireCustomer(customerLocalId);
      final effect = engine.computeRepaymentEffect(currentBalance: customer.outstandingBalance, repaymentAmount: amount);
      final now = DateTime.now();
      await (_db.update(_db.customers)..where((c) => c.localId.equals(customerLocalId))).write(
        CustomersCompanion(outstandingBalance: Value(effect.newBalance), updatedAt: Value(now)),
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
      await _db.into(_db.customerLedgerEntries).insert(entry.toDriftCompanion(syncStatus: SyncStatus.settled));
      return entry;
    });
  }

  @override
  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId) {
    final query = _db.select(_db.customerLedgerEntries).join([
      innerJoin(
        _db.customers,
        _db.customers.localId.equalsExp(_db.customerLedgerEntries.customerLocalId),
      ),
      leftOuterJoin(_db.sessions, _db.sessions.id.equals('current')),
    ])
      ..where(_db.customerLedgerEntries.customerLocalId.equals(customerLocalId))
      ..where(
        _db.sessions.id.equals('current') &
            _db.customers.locationId.equalsExp(_db.sessions.activeLocationId),
      )
      ..orderBy([
        OrderingTerm.desc(_db.customerLedgerEntries.createdAt),
        OrderingTerm.desc(_db.customerLedgerEntries.localId),
      ]);
    return query.watch().map(
          (rows) => rows
              .map((row) => row.readTable(_db.customerLedgerEntries).toDomain())
              .toList(),
        );
  }

  @override
  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
    var effectiveLocationId = locationId;
    if (effectiveLocationId == null) {
      final session = await (_db.select(_db.sessions)
            ..where((row) => row.id.equals('current')))
          .getSingleOrNull();
      effectiveLocationId = session?.activeLocationId;
    }
    if (effectiveLocationId == null) return const <CustomerLedgerEntry>[];

    final query = _db.select(_db.customerLedgerEntries).join([
      innerJoin(
        _db.customers,
        _db.customers.localId.equalsExp(_db.customerLedgerEntries.customerLocalId),
      ),
    ])
      ..where(
        _db.customerLedgerEntries.entryType.equals('repayment') &
            _db.customerLedgerEntries.createdAt.isBiggerOrEqualValue(startOfDay) &
            _db.customerLedgerEntries.createdAt.isSmallerThanValue(endExclusive) &
            _db.customers.locationId.equals(effectiveLocationId),
      )
      ..orderBy([OrderingTerm.desc(_db.customerLedgerEntries.createdAt)]);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(_db.customerLedgerEntries).toDomain())
        .toList();
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String customerServerId,
    String? saleServerId,
    required CustomerLedgerEntryType entryType,
    required Money amount,
    String? operationId,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    await _db.transaction(() async {
      final customer = await (_db.select(_db.customers)..where((c) => c.serverId.equals(customerServerId))).getSingleOrNull();
      if (customer == null) throw StateError('Canonical ledger $serverId references unknown customer $customerServerId.');
      String? saleLocalId;
      if (saleServerId != null) {
        final sale = await (_db.select(_db.sales)..where((s) => s.serverId.equals(saleServerId))).getSingleOrNull();
        if (sale == null) throw StateError('Canonical ledger $serverId references unknown sale $saleServerId.');
        saleLocalId = sale.localId;
      }
      final existingByServerId = await (_db.select(_db.customerLedgerEntries)
            ..where((e) => e.serverId.equals(serverId)))
          .getSingleOrNull();

      CustomerLedgerEntryRow? existing = existingByServerId;
      if (existing == null &&
          entryType == CustomerLedgerEntryType.repayment &&
          operationId != null &&
          operationId.isNotEmpty) {
        // A successful repayment is committed on the server before the push
        // handler receives its response and assigns serverId locally. A
        // concurrent canonical pull can therefore arrive in that window.
        // The durable outbox row is the local owner of the operation ID;
        // reuse its ledger row instead of creating a second visible entry.
        final queued = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (queued != null && queued.entityType == 'customer_ledger') {
          final candidate = await (_db.select(_db.customerLedgerEntries)
                ..where((e) => e.localId.equals(queued.entityLocalId))
                ..where((e) => e.serverId.isNull())
                ..where((e) => e.customerLocalId.equals(customer.localId))
                ..where((e) => e.entryType.equals(CustomerLedgerEntryType.repayment.name))
                ..where((e) => e.amount.equals(amount)))
              .getSingleOrNull();
          if (candidate != null) existing = candidate;
        }
      }

      // Return credit reversals are represented locally as a derived
      // refundAdjustment immediately when the return is completed offline,
      // while the authoritative server ledger event uses entry_type
      // "credit_reversal". Reuse that local projection when the canonical
      // event arrives instead of creating a duplicate ledger line.
      if (existing == null &&
          entryType == CustomerLedgerEntryType.creditSale) {
        // Credit sales are written locally as an immediate ledger echo when
        // the sale commits. The authoritative cloud ledger event arrives
        // later through the canonical change feed. Reuse that unsynced echo
        // rather than rendering a second credit-sale history row.
        final candidates = await (_db.select(_db.customerLedgerEntries)
              ..where((e) =>
                  e.serverId.isNull() &
                  e.customerLocalId.equals(customer.localId) &
                  e.entryType.equals(CustomerLedgerEntryType.creditSale.name) &
                  e.amount.equals(amount) &
                  (saleLocalId == null
                      ? e.saleLocalId.isNull()
                      : e.saleLocalId.equals(saleLocalId)))
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt)])
              ..limit(1))
            .get();
        if (candidates.isNotEmpty) existing = candidates.single;
      }
      if (existing == null && entryType == CustomerLedgerEntryType.refundAdjustment) {
        final candidates = await (_db.select(_db.customerLedgerEntries)
              ..where((e) =>
                  e.serverId.isNull() &
                  e.customerLocalId.equals(customer.localId) &
                  e.entryType.equals(CustomerLedgerEntryType.refundAdjustment.name) &
                  e.amount.equals(amount) &
                  (saleLocalId == null
                      ? e.saleLocalId.isNull()
                      : e.saleLocalId.equals(saleLocalId)))
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt)])
              ..limit(1))
            .get();
        if (candidates.isNotEmpty) existing = candidates.single;
      }

      final localId = existing?.localId ?? Ulid().toString();
      final values = CustomerLedgerEntriesCompanion(
        serverId: Value(serverId),
        customerLocalId: Value(customer.localId),
        entryType: Value(entryType.name),
        amount: Value(amount),
        paymentMethod: Value(paymentMethod),
        note: Value(note),
        saleLocalId: Value(saleLocalId),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        syncStatus: const Value(SyncStatus.settled),
      );
      if (existing == null) {
        await _db.into(_db.customerLedgerEntries).insert(
          CustomerLedgerEntriesCompanion.insert(
            localId: localId,
            serverId: Value(serverId),
            customerLocalId: customer.localId,
            entryType: entryType.name,
            amount: amount,
            paymentMethod: Value(paymentMethod),
            note: Value(note),
            saleLocalId: Value(saleLocalId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: SyncStatus.settled,
          ),
        );
      } else {
        await (_db.update(_db.customerLedgerEntries)..where((e) => e.localId.equals(localId))).write(values);
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.customerLedgerEntries)..where((e) => e.serverId.equals(serverId))).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.customerLedgerEntries)..where((e) => e.localId.equals(row.localId))).write(
      CustomerLedgerEntriesCompanion(updatedAt: Value(now), syncStatus: const Value(SyncStatus.settled)),
    );
  }
}
