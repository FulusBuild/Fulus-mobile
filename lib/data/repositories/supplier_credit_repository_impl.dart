import '../../core/money/money.dart';
import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/customer_credit_engine.dart' as engine;
import '../../domain/entities/supplier_ledger_entry.dart';
import '../../domain/repositories/supplier_credit_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../../sync/sync_queue.dart';
import 'supplier_ledger_mapper.dart';

class SupplierCreditRepositoryImpl implements SupplierCreditRepository {
  SupplierCreditRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  }) : _db = db,
       _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  Future<SupplierRow> _requireSupplier(String localId) async {
    final row =
        await (_db.select(_db.suppliers)
              ..where((s) => s.localId.equals(localId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(localId, 'supplierLocalId', 'no such supplier');
    }
    return row;
  }

  @override
  Future<SupplierLedgerEntry> recordStockPurchaseOnCredit({
    required String supplierLocalId,
    required Money amount,
    String? stockMovementLocalId,
    required String locationLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final supplier = await _requireSupplier(supplierLocalId);
      final attributedLocationId = locationLocalId;
      final location =
          await (_db.select(_db.locations)
                ..where((row) => row.localId.equals(attributedLocationId)))
              .getSingleOrNull();
      if (location == null || location.deletedAt != null) {
        throw ArgumentError.value(
          locationLocalId,
          'locationLocalId',
          'must identify an active location',
        );
      }
      if (stockMovementLocalId != null) {
        final movement =
            await (_db.select(_db.stockMovements)
                  ..where((row) => row.localId.equals(stockMovementLocalId)))
                .getSingleOrNull();
        if (movement == null) {
          throw ArgumentError.value(
            stockMovementLocalId,
            'stockMovementLocalId',
            'no such stock movement',
          );
        }
        if (attributedLocationId != movement.locationId) {
          throw ArgumentError.value(
            locationLocalId,
            'locationLocalId',
            'must match the stock movement location',
          );
        }
      }
      final now = DateTime.now();
      final newBalance = supplier.outstandingBalance + amount;

      await (_db.update(
        _db.suppliers,
      )..where((s) => s.localId.equals(supplierLocalId))).write(
        SuppliersCompanion(
          outstandingBalance: Value(newBalance),
          updatedAt: Value(now),
        ),
      );

      final entry = SupplierLedgerEntry(
        localId: Ulid().toString(),
        supplierLocalId: supplierLocalId,
        entryType: SupplierLedgerEntryType.stockPurchaseOnCredit,
        amount: amount,
        locationLocalId: attributedLocationId,
        stockMovementLocalId: stockMovementLocalId,
        createdAt: now,
      );
      await _db
          .into(_db.supplierLedgerEntries)
          .insert(entry.toDriftCompanion());
      await _syncQueue.enqueue(
        SyncTask.recordSupplierLedgerEntry(entry.localId),
      );
      return entry;
    });
  }

  @override
  Future<({SupplierLedgerEntry entry, Money newBalance, Money excessAmount})>
  recordPayment({
    required String supplierLocalId,
    required Money amount,
    String? paymentMethod,
    String? note,
    required String locationLocalId,
    String? cashDrawerShiftLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final supplier = await _requireSupplier(supplierLocalId);
      final attributedLocationId = locationLocalId;
      final location =
          await (_db.select(_db.locations)
                ..where((row) => row.localId.equals(attributedLocationId)))
              .getSingleOrNull();
      if (location == null || location.deletedAt != null) {
        throw ArgumentError.value(
          locationLocalId,
          'locationLocalId',
          'must identify an active location',
        );
      }
      if (cashDrawerShiftLocalId != null) {
        if (paymentMethod?.trim().toLowerCase() != 'cash') {
          throw ArgumentError.value(
            paymentMethod,
            'paymentMethod',
            'only cash payments can be assigned to a drawer session',
          );
        }
        final shift =
            await (_db.select(_db.cashDrawerShifts)..where(
                  (s) =>
                      s.localId.equals(cashDrawerShiftLocalId) &
                      s.closedAt.isNull(),
                ))
                .getSingleOrNull();
        if (shift == null) {
          throw ArgumentError.value(
            cashDrawerShiftLocalId,
            'cashDrawerShiftLocalId',
            'must identify an open cash drawer session',
          );
        }
        if (attributedLocationId != shift.locationId) {
          throw ArgumentError.value(
            attributedLocationId,
            'locationLocalId',
            'must match the cash drawer session location',
          );
        }
      }
      // Reused directly from CustomerCreditRepositoryImpl's own
      // engine — the clamp-at-zero-and-report-any-excess math is
      // identical regardless of which side of the ledger it's applied
      // to; duplicating it here under a different name would just be
      // two copies of the same rule to keep in sync.
      final effect = engine.computeRepaymentEffect(
        currentBalance: supplier.outstandingBalance,
        repaymentAmount: amount,
      );
      final now = DateTime.now();

      await (_db.update(
        _db.suppliers,
      )..where((s) => s.localId.equals(supplierLocalId))).write(
        SuppliersCompanion(
          outstandingBalance: Value(effect.newBalance),
          updatedAt: Value(now),
        ),
      );

      final entry = SupplierLedgerEntry(
        localId: Ulid().toString(),
        supplierLocalId: supplierLocalId,
        entryType: SupplierLedgerEntryType.paymentMade,
        amount: amount,
        locationLocalId: attributedLocationId,
        paymentMethod: paymentMethod,
        note: note,
        cashDrawerShiftLocalId: cashDrawerShiftLocalId,
        createdAt: now,
      );
      await _db
          .into(_db.supplierLedgerEntries)
          .insert(entry.toDriftCompanion());
      await _syncQueue.enqueue(
        SyncTask.recordSupplierLedgerEntry(entry.localId),
      );

      return (
        entry: entry,
        newBalance: effect.newBalance,
        excessAmount: effect.excessAmount,
      );
    });
  }

  @override
  Stream<List<SupplierLedgerEntry>> watchLedger(String supplierLocalId) {
    final query = _db.select(_db.supplierLedgerEntries)
      ..where((e) => e.supplierLocalId.equals(supplierLocalId))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<List<SupplierLedgerEntry>> getPaymentsForPeriod({
    required DateTime start,
    required DateTime end,
    String? locationLocalId,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));

    // 'paymentMade' — the same textEnum WHERE-clause comparison
    // FinanceStatsRepositoryImpl.getCashFlow already verified working
    // against this exact column (`e.entryType.equals('paymentMade')`).
    final rows =
        await (_db.select(_db.supplierLedgerEntries)
              ..where(
                (e) =>
                    e.entryType.equals('paymentMade') &
                    (locationLocalId == null
                        ? const Constant(true)
                        : e.locationLocalId.equals(locationLocalId)) &
                    e.createdAt.isBiggerOrEqualValue(startOfDay) &
                    e.createdAt.isSmallerThanValue(endExclusive),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
            .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<void> reconcileServerEntry({
    required String serverId,
    required String operationId,
    required String supplierServerId,
    required String locationServerId,
    String? stockMovementServerId,
    String? cashDrawerShiftServerId,
    required SupplierLedgerEntryType entryType,
    required Money amount,
    required Money balanceAfter,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
  }) async {
    await _db.transaction(() async {
      final supplier =
          await (_db.select(_db.suppliers)
                ..where((row) => row.serverId.equals(supplierServerId)))
              .getSingleOrNull();
      if (supplier == null) {
        throw StateError(
          'Supplier $supplierServerId must be restored before its ledger.',
        );
      }
      final location =
          await (_db.select(_db.locations)
                ..where((row) => row.serverId.equals(locationServerId)))
              .getSingleOrNull();
      if (location == null) {
        throw StateError(
          'Location $locationServerId must be restored before its supplier ledger.',
        );
      }
      final movement = stockMovementServerId == null
          ? null
          : await (_db.select(_db.stockMovements)
                  ..where((row) => row.serverId.equals(stockMovementServerId)))
                .getSingleOrNull();
      if (stockMovementServerId != null && movement == null) {
        throw StateError(
          'Stock movement $stockMovementServerId must be restored before its supplier ledger.',
        );
      }
      final shift = cashDrawerShiftServerId == null
          ? null
          : await (_db.select(
                  _db.cashDrawerShifts,
                )..where((row) => row.serverId.equals(cashDrawerShiftServerId)))
                .getSingleOrNull();
      if (cashDrawerShiftServerId != null && shift == null) {
        throw StateError(
          'Cash drawer $cashDrawerShiftServerId must be restored before its supplier ledger.',
        );
      }

      final queuedOperation =
          await (_db.select(_db.syncQueueItems)
                ..where((row) => row.id.equals(operationId))
                ..where((row) => row.entityType.equals('supplier_ledger')))
              .getSingleOrNull();
      final existingByServerId = await (_db.select(
        _db.supplierLedgerEntries,
      )..where((row) => row.serverId.equals(serverId))).getSingleOrNull();
      final localId =
          existingByServerId?.localId ??
          queuedOperation?.entityLocalId ??
          Ulid().toString();
      final existing =
          existingByServerId ??
          await (_db.select(
            _db.supplierLedgerEntries,
          )..where((row) => row.localId.equals(localId))).getSingleOrNull();
      final companion = SupplierLedgerEntriesCompanion(
        serverId: Value(serverId),
        supplierLocalId: Value(supplier.localId),
        locationLocalId: Value(location.localId),
        entryType: Value(entryType.name),
        amount: Value(amount),
        paymentMethod: Value(paymentMethod),
        note: Value(note),
        stockMovementLocalId: Value(movement?.localId),
        cashDrawerShiftLocalId: Value(shift?.localId),
        createdAt: Value(createdAt),
        updatedAt: Value(createdAt),
        syncStatus: const Value(SyncStatus.settled),
        deletedAt: const Value(null),
      );
      if (existing == null) {
        await _db
            .into(_db.supplierLedgerEntries)
            .insert(
              SupplierLedgerEntriesCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                supplierLocalId: supplier.localId,
                locationLocalId: Value(location.localId),
                entryType: entryType.name,
                amount: amount,
                paymentMethod: Value(paymentMethod),
                note: Value(note),
                stockMovementLocalId: Value(movement?.localId),
                cashDrawerShiftLocalId: Value(shift?.localId),
                createdAt: createdAt,
                updatedAt: createdAt,
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(
          _db.supplierLedgerEntries,
        )..where((row) => row.localId.equals(localId))).write(companion);
      }

      final pending =
          await (_db.select(_db.syncQueueItems)
                ..where((row) => row.entityType.equals('supplier_ledger'))
                ..where((row) => row.id.isNotIn([operationId])))
              .get();
      var hasOtherPendingForSupplier = false;
      for (final item in pending) {
        final other =
            await (_db.select(_db.supplierLedgerEntries)
                  ..where((row) => row.localId.equals(item.entityLocalId)))
                .getSingleOrNull();
        if (other?.supplierLocalId == supplier.localId) {
          hasOtherPendingForSupplier = true;
          break;
        }
      }
      if (!hasOtherPendingForSupplier) {
        await (_db.update(
          _db.suppliers,
        )..where((row) => row.localId.equals(supplier.localId))).write(
          SuppliersCompanion(
            outstandingBalance: Value(balanceAfter),
            updatedAt: Value(createdAt),
          ),
        );
      }
    });
  }
}
