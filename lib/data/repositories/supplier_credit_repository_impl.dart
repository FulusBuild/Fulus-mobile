import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/customer_credit_engine.dart' as engine;
import '../../domain/entities/supplier_ledger_entry.dart';
import '../../domain/repositories/supplier_credit_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'supplier_ledger_mapper.dart';

class SupplierCreditRepositoryImpl implements SupplierCreditRepository {
  SupplierCreditRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  Future<SupplierRow> _requireSupplier(String localId) async {
    final row = await (_db.select(_db.suppliers)
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
    required double amount,
    String? stockMovementLocalId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final supplier = await _requireSupplier(supplierLocalId);
      final now = DateTime.now();
      final newBalance = supplier.outstandingBalance + amount;

      await (_db.update(_db.suppliers)
            ..where((s) => s.localId.equals(supplierLocalId)))
          .write(
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
        stockMovementLocalId: stockMovementLocalId,
        createdAt: now,
      );
      await _db
          .into(_db.supplierLedgerEntries)
          .insert(entry.toDriftCompanion());
      return entry;
    });
  }

  @override
  Future<
      ({
        SupplierLedgerEntry entry,
        double newBalance,
        double excessAmount,
      })> recordPayment({
    required String supplierLocalId,
    required double amount,
    String? paymentMethod,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    return _db.transaction(() async {
      final supplier = await _requireSupplier(supplierLocalId);
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

      await (_db.update(_db.suppliers)
            ..where((s) => s.localId.equals(supplierLocalId)))
          .write(
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
        paymentMethod: paymentMethod,
        note: note,
        createdAt: now,
      );
      await _db
          .into(_db.supplierLedgerEntries)
          .insert(entry.toDriftCompanion());

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
}
