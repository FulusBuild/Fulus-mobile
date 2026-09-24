import 'package:drift/drift.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/customer_ledger_entry.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_seed_helpers.dart';

void main() {
  late AppDatabase db;
  late CustomerRepositoryImpl customerRepository;
  late CustomerCreditRepositoryImpl creditRepository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final syncQueue = SyncQueue(db);
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
    creditRepository = CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db));

    // CustomerLedgerEntries.saleLocalId is a real FK against
    // sales(local_id) — every test in this file links its ledger
    // entries to 'sale-1' and/or 'sale-2', so those rows have to exist
    // first.
    await seedSale(db, localId: 'sale-1');
    await seedSale(db, localId: 'sale-2');
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createTestCustomer() async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Ngozi Eze'),
    );
    return customer.localId;
  }

  group('recordCreditSale', () {
    test('increases the customer\'s outstanding balance', () async {
      final customerId = await createTestCustomer();

      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );

      final customer = await customerRepository.getCustomerById(customerId);
      expect(customer!.outstandingBalance, 5000);
    });

    test('writes a creditSale ledger entry linked to the sale', () async {
      final customerId = await createTestCustomer();

      final entry = await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );

      expect(entry.entryType, CustomerLedgerEntryType.creditSale);
      expect(entry.saleLocalId, 'sale-1');
      expect(entry.amount, 5000);
    });

    test('two credit sales accumulate', () async {
      final customerId = await createTestCustomer();

      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 3000,
        saleLocalId: 'sale-1',
      );
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 2000,
        saleLocalId: 'sale-2',
      );

      final customer = await customerRepository.getCustomerById(customerId);
      expect(customer!.outstandingBalance, 5000);
    });

    test('rejects a non-positive amount', () async {
      final customerId = await createTestCustomer();
      await expectLater(
        creditRepository.recordCreditSale(
          customerLocalId: customerId,
          amount: 0,
          saleLocalId: 'sale-1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('recordRepayment', () {
    test('reduces the balance by the repayment amount', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 10000,
        saleLocalId: 'sale-1',
      );

      final result = await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 4000,
        paymentMethod: 'cash',
      );

      expect(result.newBalance, 6000);
      expect(result.excessAmount, 0.0);
      final customer = await customerRepository.getCustomerById(customerId);
      expect(customer!.outstandingBalance, 6000);
    });

    test(
        'a repayment larger than the balance clamps at zero and reports '
        'the excess (Volume 7 failure scenario)', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 3000,
        saleLocalId: 'sale-1',
      );

      final result = await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 5000,
      );

      expect(result.newBalance, 0.0);
      expect(result.excessAmount, 2000);
      final customer = await customerRepository.getCustomerById(customerId);
      expect(customer!.outstandingBalance, 0.0);
    });

    test('the stored ledger entry keeps the full amount tendered, not the '
        'capped applied amount', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 3000,
        saleLocalId: 'sale-1',
      );

      final result = await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 5000,
      );

      expect(result.entry.amount, 5000);
    });

    test('a freestanding repayment (no saleLocalId) still works', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 2000,
        saleLocalId: 'sale-1',
      );

      final result = await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 2000,
      );

      expect(result.entry.saleLocalId, isNull);
      expect(result.newBalance, 0.0);
    });

    test('rejects a non-positive amount', () async {
      final customerId = await createTestCustomer();
      await expectLater(
        creditRepository.recordRepayment(customerLocalId: customerId, amount: -1),
        throwsArgumentError,
      );
    });
  });

  test('rolls back the local repayment when outbox enqueue fails', () async {
    final customerId = await createTestCustomer();
    await creditRepository.recordCreditSale(
      customerLocalId: customerId,
      amount: 5000,
      saleLocalId: 'sale-1',
    );

    final throwingQueue = _ThrowingSyncQueue(db);
    final repository = CustomerCreditRepositoryImpl(
      db: db,
      syncQueue: throwingQueue,
    );

    await expectLater(
      repository.recordRepayment(
        customerLocalId: customerId,
        amount: 2000,
      ),
      throwsA(isA<StateError>()),
    );

    final customer = await customerRepository.getCustomerById(customerId);
    expect(customer!.outstandingBalance, 5000);
    final entries = await (db.select(db.customerLedgerEntries)
          ..where((e) => e.customerLocalId.equals(customerId)))
        .get();
    expect(entries, hasLength(1));
    expect(entries.single.entryType, 'creditSale');
  });

  group('recordRefundAdjustment', () {
    test('reduces the balance the same way a repayment does', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 8000,
        saleLocalId: 'sale-1',
      );

      final entry = await creditRepository.recordRefundAdjustment(
        customerLocalId: customerId,
        amount: 3000,
        saleLocalId: 'sale-1',
      );

      expect(entry.entryType, CustomerLedgerEntryType.refundAdjustment);
      final customer = await customerRepository.getCustomerById(customerId);
      expect(customer!.outstandingBalance, 5000);
    });

    test('canonical return credit reversal attaches to the existing local adjustment', () async {
      final customerId = await createTestCustomer();
      await (db.update(db.customers)..where((c) => c.localId.equals(customerId))).write(
        const CustomersCompanion(serverId: Value('customer-server-1')),
      );
      await (db.update(db.sales)..where((s) => s.localId.equals('sale-1'))).write(
        const SalesCompanion(serverId: Value('sale-server-1')),
      );

      final localEntry = await creditRepository.recordRefundAdjustment(
        customerLocalId: customerId,
        amount: 3000,
        saleLocalId: 'sale-1',
      );

      await creditRepository.reconcileServerState(
        serverId: 'ledger-server-1',
        customerServerId: 'customer-server-1',
        saleServerId: 'sale-server-1',
        entryType: CustomerLedgerEntryType.refundAdjustment,
        amount: 3000,
        note: 'Return credit reversal',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final rows = await (db.select(db.customerLedgerEntries)
            ..where((e) => e.customerLocalId.equals(customerId)))
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.localId, localEntry.localId);
      expect(rows.single.serverId, 'ledger-server-1');
      expect(rows.single.entryType, 'refundAdjustment');
    });
  });

  group('getRepaymentsForPeriod', () {
    test('includes a repayment made today when the period covers today', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );
      final repayment = await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 2000,
      );

      final today = DateTime.now();
      final results = await creditRepository.getRepaymentsForPeriod(start: today, end: today);

      expect(results.map((e) => e.localId), contains(repayment.entry.localId));
    });

    test('excludes a creditSale entry even though it is in range — only repayment counts',
        () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );

      final today = DateTime.now();
      final results = await creditRepository.getRepaymentsForPeriod(start: today, end: today);

      expect(results, isEmpty);
    });

    test('excludes a repayment outside the requested range', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );
      await creditRepository.recordRepayment(customerLocalId: customerId, amount: 2000);

      final farFuture = DateTime.now().add(const Duration(days: 365));
      final results =
          await creditRepository.getRepaymentsForPeriod(start: farFuture, end: farFuture);

      expect(results, isEmpty);
    });
  });

  group('watchLedger', () {
    test('emits entries reverse-chronologically', () async {
      final customerId = await createTestCustomer();
      await creditRepository.recordCreditSale(
        customerLocalId: customerId,
        amount: 5000,
        saleLocalId: 'sale-1',
      );

      // The production ordering is by createdAt. Give the two domain events
      // distinct timestamps rather than relying on two back-to-back calls to
      // DateTime.now() having different microsecond values on every runner.
      await Future<void>.delayed(const Duration(milliseconds: 2));

      await creditRepository.recordRepayment(
        customerLocalId: customerId,
        amount: 2000,
      );

      final entries = await creditRepository.watchLedger(customerId).first;

      expect(entries, hasLength(2));
      expect(entries.first.entryType, CustomerLedgerEntryType.repayment);
      expect(entries.last.entryType, CustomerLedgerEntryType.creditSale);
    });
  });
}

class _ThrowingSyncQueue extends SyncQueue {
  _ThrowingSyncQueue(super.db);

  @override
  Future<void> enqueue(SyncTask task) async {
    throw StateError('simulated outbox failure');
  }
}
