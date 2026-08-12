import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/supplier_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/supplier_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/supplier.dart';
import 'package:fulus_mobile/domain/entities/supplier_ledger_entry.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SupplierRepositoryImpl supplierRepository;
  late SupplierCreditRepositoryImpl creditRepository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final syncQueue = SyncQueue(db);
    supplierRepository = SupplierRepositoryImpl(db: db, syncQueue: syncQueue);
    creditRepository = SupplierCreditRepositoryImpl(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createTestSupplier() async {
    final supplier = await supplierRepository.createSupplier(
      const SupplierDraft(name: 'ABC Distributors'),
    );
    return supplier.localId;
  }

  group('recordStockPurchaseOnCredit', () {
    test("increases the supplier's outstanding balance", () async {
      final supplierId = await createTestSupplier();

      await creditRepository.recordStockPurchaseOnCredit(
        supplierLocalId: supplierId,
        amount: 20000,
      );

      final supplier = await supplierRepository.getSupplierById(supplierId);
      expect(supplier!.outstandingBalance, 20000);
    });

    test('writes a stockPurchaseOnCredit ledger entry', () async {
      final supplierId = await createTestSupplier();

      final entry = await creditRepository.recordStockPurchaseOnCredit(
        supplierLocalId: supplierId,
        amount: 20000,
      );

      expect(entry.entryType, SupplierLedgerEntryType.stockPurchaseOnCredit);
      expect(entry.amount, 20000);
    });

    test('two purchases accumulate', () async {
      final supplierId = await createTestSupplier();

      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 12000);
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 8000);

      final supplier = await supplierRepository.getSupplierById(supplierId);
      expect(supplier!.outstandingBalance, 20000);
    });
  });

  group('recordPayment', () {
    test('reduces the balance by the payment amount', () async {
      final supplierId = await createTestSupplier();
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 20000);

      final result = await creditRepository.recordPayment(
        supplierLocalId: supplierId,
        amount: 8000,
        paymentMethod: 'cash',
      );

      expect(result.newBalance, 12000);
      expect(result.entry.entryType, SupplierLedgerEntryType.paymentMade);
      expect(result.excessAmount, 0.0);
      final supplier = await supplierRepository.getSupplierById(supplierId);
      expect(supplier!.outstandingBalance, 12000);
    });

    test('a payment larger than the balance clamps at zero and reports the excess', () async {
      final supplierId = await createTestSupplier();
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 5000);

      final result = await creditRepository.recordPayment(supplierLocalId: supplierId, amount: 9000);

      expect(result.newBalance, 0.0);
      expect(result.excessAmount, 4000);
    });
  });

  group('getPaymentsForPeriod', () {
    test('includes a payment made today when the period covers today', () async {
      final supplierId = await createTestSupplier();
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 20000);
      final result = await creditRepository.recordPayment(supplierLocalId: supplierId, amount: 8000);

      final today = DateTime.now();
      final results = await creditRepository.getPaymentsForPeriod(start: today, end: today);

      expect(results.map((e) => e.localId), contains(result.entry.localId));
    });

    test('excludes a stockPurchase entry even though it is in range — only paymentMade counts',
        () async {
      final supplierId = await createTestSupplier();
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 20000);

      final today = DateTime.now();
      final results = await creditRepository.getPaymentsForPeriod(start: today, end: today);

      expect(results, isEmpty);
    });

    test('excludes a payment outside the requested range', () async {
      final supplierId = await createTestSupplier();
      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 20000);
      await creditRepository.recordPayment(supplierLocalId: supplierId, amount: 8000);

      final farFuture = DateTime.now().add(const Duration(days: 365));
      final results = await creditRepository.getPaymentsForPeriod(start: farFuture, end: farFuture);

      expect(results, isEmpty);
    });
  });

  group('watchLedger', () {
    test('emits entries for the given supplier only', () async {
      final supplierId = await createTestSupplier();
      final otherSupplierId = await supplierRepository
          .createSupplier(const SupplierDraft(name: 'Other Supplier'))
          .then((s) => s.localId);

      await creditRepository.recordStockPurchaseOnCredit(supplierLocalId: supplierId, amount: 1000);
      await creditRepository.recordStockPurchaseOnCredit(
        supplierLocalId: otherSupplierId,
        amount: 2000,
      );

      final entries = await creditRepository.watchLedger(supplierId).first;

      expect(entries, hasLength(1));
      expect(entries.single.supplierLocalId, supplierId);
    });
  });
}
