import 'package:fulus_mobile/domain/entities/cash_drawer_shift.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/customer_ledger_entry.dart';
import 'package:fulus_mobile/domain/entities/expense.dart';
import 'package:fulus_mobile/domain/entities/expense_category.dart';
import 'package:fulus_mobile/domain/entities/income_record.dart';
import 'package:fulus_mobile/domain/entities/report.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/supplier.dart';
import 'package:fulus_mobile/domain/entities/supplier_ledger_entry.dart';
import 'package:fulus_mobile/domain/repositories/cash_drawer_shift_repository.dart';
import 'package:fulus_mobile/domain/repositories/customer_credit_repository.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';
import 'package:fulus_mobile/domain/repositories/expense_category_repository.dart';
import 'package:fulus_mobile/domain/repositories/expense_repository.dart';
import 'package:fulus_mobile/domain/repositories/income_record_repository.dart';
import 'package:fulus_mobile/domain/repositories/sale_repository.dart';
import 'package:fulus_mobile/domain/repositories/supplier_credit_repository.dart';
import 'package:fulus_mobile/domain/repositories/supplier_repository.dart';
import 'package:fulus_mobile/domain/usecases/active_location_resolver.dart';
import 'package:fulus_mobile/features/money/data/real_money_repository.dart';
import 'package:fulus_mobile/features/money/domain/money_transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSaleRepository extends Mock implements SaleRepository {}

class MockExpenseRepository extends Mock implements ExpenseRepository {}

class MockIncomeRecordRepository extends Mock implements IncomeRecordRepository {}

class MockCustomerCreditRepository extends Mock implements CustomerCreditRepository {}

class MockSupplierCreditRepository extends Mock implements SupplierCreditRepository {}

class MockCashDrawerShiftRepository extends Mock implements CashDrawerShiftRepository {}

class MockExpenseCategoryRepository extends Mock implements ExpenseCategoryRepository {}

class MockCustomerRepository extends Mock implements CustomerRepository {}

class MockSupplierRepository extends Mock implements SupplierRepository {}

class MockResolveActiveLocation extends Mock implements ResolveActiveLocation {}

void main() {
  late MockSaleRepository saleRepository;
  late MockExpenseRepository expenseRepository;
  late MockIncomeRecordRepository incomeRecordRepository;
  late MockCustomerCreditRepository customerCreditRepository;
  late MockSupplierCreditRepository supplierCreditRepository;
  late MockCashDrawerShiftRepository cashDrawerShiftRepository;
  late MockExpenseCategoryRepository expenseCategoryRepository;
  late MockCustomerRepository customerRepository;
  late MockSupplierRepository supplierRepository;
  late MockResolveActiveLocation resolveActiveLocation;
  late RealMoneyRepositoryImpl repository;

  final now = DateTime(2026, 1, 1);

  final testCategory = ExpenseCategory(
    localId: 'cat-1',
    name: 'Fuel & Transport',
    createdAt: now,
    updatedAt: now,
  );
  final testCustomer = Customer(
    localId: 'cust-1',
    name: 'Ngozi Eze',
    outstandingBalance: 0,
    purchaseCount: 3,
    createdAt: now,
    updatedAt: now,
  );
  final testSupplier = Supplier(localId: 'sup-1', name: 'ABC Distributors', createdAt: now, updatedAt: now);

  final testSale = Sale(
    localId: 'sale-1',
    locationId: 'loc-1',
    invoiceNumber: 'INV-001',
    saleDate: DateTime(2026, 7, 15),
    subtotal: 1000,
    taxAmount: 0,
    discountAmount: 0,
    total: 1000,
    amountPaid: 1000,
    balanceDue: 0,
    paymentMethod: 'cash',
    cashierUserId: 'user-1',
    items: const [],
  );
  final testExpense = Expense(
    localId: 'expense-1',
    locationId: 'loc-1',
    categoryId: 'cat-1',
    description: 'Fuel',
    amount: 300,
    expenseDate: DateTime(2026, 7, 16),
    paymentMethod: 'cash',
  );
  final testIncome = IncomeRecord(
    localId: 'income-1',
    locationId: 'loc-1',
    source: 'Equipment rental',
    amount: 200,
    incomeDate: DateTime(2026, 7, 17),
  );
  final testRepayment = CustomerLedgerEntry(
    localId: 'repayment-1',
    customerLocalId: 'cust-1',
    entryType: CustomerLedgerEntryType.repayment,
    amount: 150,
    paymentMethod: 'cash',
    createdAt: DateTime(2026, 7, 18),
    updatedAt: DateTime(2026, 7, 18),
  );
  final testPayment = SupplierLedgerEntry(
    localId: 'payment-1',
    supplierLocalId: 'sup-1',
    entryType: SupplierLedgerEntryType.paymentMade,
    amount: 100,
    paymentMethod: 'card',
    createdAt: DateTime(2026, 7, 19),
  );

  final testPeriod = ReportPeriod(
    kind: ReportPeriodKind.custom,
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );

  setUpAll(() {
    registerFallbackValue(const ExpenseCategoryDraft(name: 'fallback'));
    registerFallbackValue(ExpenseDraft(
      locationId: 'loc-1',
      description: 'fallback',
      amount: 0,
      expenseDate: DateTime(2026, 1, 1),
    ));
    registerFallbackValue(IncomeRecordDraft(
      locationId: 'loc-1',
      source: 'fallback',
      amount: 0,
      incomeDate: DateTime(2026, 1, 1),
    ));
  });

  setUp(() {
    saleRepository = MockSaleRepository();
    expenseRepository = MockExpenseRepository();
    incomeRecordRepository = MockIncomeRecordRepository();
    customerCreditRepository = MockCustomerCreditRepository();
    supplierCreditRepository = MockSupplierCreditRepository();
    cashDrawerShiftRepository = MockCashDrawerShiftRepository();
    expenseCategoryRepository = MockExpenseCategoryRepository();
    customerRepository = MockCustomerRepository();
    supplierRepository = MockSupplierRepository();
    resolveActiveLocation = MockResolveActiveLocation();

    repository = RealMoneyRepositoryImpl(
      saleRepository: saleRepository,
      expenseRepository: expenseRepository,
      incomeRecordRepository: incomeRecordRepository,
      customerCreditRepository: customerCreditRepository,
      supplierCreditRepository: supplierCreditRepository,
      cashDrawerShiftRepository: cashDrawerShiftRepository,
      expenseCategoryRepository: expenseCategoryRepository,
      customerRepository: customerRepository,
      supplierRepository: supplierRepository,
      resolveActiveLocation: resolveActiveLocation,
    );

    when(() => resolveActiveLocation.call()).thenAnswer((_) async => 'loc-1');
    when(() => saleRepository.getSalesForPeriod(
          locationId: any(named: 'locationId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        )).thenAnswer((_) async => [testSale]);
    when(() => expenseRepository.getExpensesForPeriod(
          locationId: any(named: 'locationId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        )).thenAnswer((_) async => [testExpense]);
    when(() => incomeRecordRepository.getIncomeRecordsForPeriod(
          locationId: any(named: 'locationId'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        )).thenAnswer((_) async => [testIncome]);
    when(() => customerCreditRepository.getRepaymentsForPeriod(
          start: any(named: 'start'),
          end: any(named: 'end'),
        )).thenAnswer((_) async => [testRepayment]);
    when(() => supplierCreditRepository.getPaymentsForPeriod(
          start: any(named: 'start'),
          end: any(named: 'end'),
        )).thenAnswer((_) async => [testPayment]);
    when(() => expenseCategoryRepository.watchExpenseCategories())
        .thenAnswer((_) => Stream.value([testCategory]));
    when(() => customerRepository.getCustomerById('cust-1'))
        .thenAnswer((_) async => testCustomer);
    when(() => supplierRepository.getSupplierById('sup-1'))
        .thenAnswer((_) async => testSupplier);
  });

  group('getSummary', () {
    test('sums inflow across sales, other income, and repayments', () async {
      final summary = await repository.getSummary(testPeriod);

      // 1000 (sale, cash-basis amountPaid) + 200 (manual income) + 150
      // (repayment) — NOT including the sale's full `total` twice over.
      expect(summary.moneyIn, 1350);
    });

    test('sums outflow across expenses and supplier payments', () async {
      final summary = await repository.getSummary(testPeriod);

      expect(summary.moneyOut, 400);
    });

    test('counts every transaction across all five sources', () async {
      final summary = await repository.getSummary(testPeriod);
      expect(summary.transactionCount, 5);
    });

    test('breaks income down into sales/repayments/other, each correctly labeled', () async {
      final summary = await repository.getSummary(testPeriod);

      final byLabel = {for (final row in summary.incomeBreakdown) row.label: row.amount};
      expect(byLabel['Sales income'], 1000);
      expect(byLabel['Customer repayments'], 150);
      expect(byLabel['Other income'], 200);
    });

    test('breaks expenses down by category name, with supplier payments as their own row',
        () async {
      final summary = await repository.getSummary(testPeriod);

      final byLabel = {for (final row in summary.expenseBreakdown) row.label: row.amount};
      expect(byLabel['Fuel & Transport'], 300);
      expect(byLabel['Supplier payments'], 100);
    });
  });

  group('getTransactions', () {
    test('filters by type', () async {
      final results = await repository.getTransactions(
        testPeriod,
        typeFilter: MoneyTransactionType.expense,
      );

      expect(results, hasLength(1));
      expect(results.single.type, MoneyTransactionType.expense);
    });

    test('filters by search query across title/subtitle/counterparty/reference', () async {
      final results = await repository.getTransactions(testPeriod, searchQuery: 'INV-001');

      expect(results, hasLength(1));
      expect(results.single.type, MoneyTransactionType.saleIncome);
    });

    test('a search query matching nothing returns an empty list', () async {
      final results = await repository.getTransactions(testPeriod, searchQuery: 'nonexistent');
      expect(results, isEmpty);
    });
  });

  group('payment method normalization', () {
    test('a sale/expense stored as lowercase "cash" displays as "Cash"', () async {
      final results = await repository.getTransactions(
        testPeriod,
        typeFilter: MoneyTransactionType.saleIncome,
      );
      expect(results.single.paymentMethod, 'Cash');
    });

    test('a supplier payment stored as "card" displays as "Card"', () async {
      final results = await repository.getTransactions(
        testPeriod,
        typeFilter: MoneyTransactionType.supplierPayment,
      );
      expect(results.single.paymentMethod, 'Card');
    });
  });

  group('recordExpense', () {
    test('reuses an existing category by case-insensitive name match', () async {
      when(() => expenseRepository.recordExpense(any())).thenAnswer((_) async => testExpense);

      await repository.recordExpense(amount: 300, category: 'fuel & transport', paymentMethod: 'Cash');

      verifyNever(() => expenseCategoryRepository.createExpenseCategory(any()));
      final captured = verify(() => expenseRepository.recordExpense(captureAny())).captured;
      final draft = captured.single as ExpenseDraft;
      expect(draft.categoryId, 'cat-1');
    });

    test('creates a new category when no existing one matches', () async {
      when(() => expenseCategoryRepository.createExpenseCategory(any())).thenAnswer(
        (_) async => ExpenseCategory(localId: 'cat-2', name: 'Wages', createdAt: now, updatedAt: now),
      );
      when(() => expenseRepository.recordExpense(any())).thenAnswer((_) async => testExpense);

      await repository.recordExpense(amount: 500, category: 'Wages', paymentMethod: 'Cash');

      final captured = verify(() => expenseRepository.recordExpense(captureAny())).captured;
      final draft = captured.single as ExpenseDraft;
      expect(draft.categoryId, 'cat-2');
    });

    test('normalizes the display payment method to the lowercase storage key', () async {
      when(() => expenseRepository.recordExpense(any())).thenAnswer((_) async => testExpense);

      await repository.recordExpense(amount: 300, category: 'Fuel & Transport', paymentMethod: 'Bank/Card');

      final captured = verify(() => expenseRepository.recordExpense(captureAny())).captured;
      final draft = captured.single as ExpenseDraft;
      // 'Bank/Card' -> 'card', not a fragmented new key — see
      // RealMoneyRepositoryImpl._toStorageKey's own doc comment for
      // why this matters to CashDrawerShiftRepositoryImpl.
      // computeExpectedCash's existing lowercase 'cash' query.
      expect(draft.paymentMethod, 'card');
    });

    test('uses the note as description when given, category name otherwise', () async {
      when(() => expenseRepository.recordExpense(any())).thenAnswer((_) async => testExpense);

      await repository.recordExpense(
        amount: 300,
        category: 'Fuel & Transport',
        paymentMethod: 'Cash',
        note: 'Diesel for the delivery van',
      );

      final captured = verify(() => expenseRepository.recordExpense(captureAny())).captured;
      final draft = captured.single as ExpenseDraft;
      expect(draft.description, 'Diesel for the delivery van');
    });
  });

  group('recordIncome', () {
    test('delegates to IncomeRecordRepository with the resolved location', () async {
      when(() => incomeRecordRepository.recordIncome(any())).thenAnswer((_) async => testIncome);

      await repository.recordIncome(amount: 200, source: 'Equipment rental', note: 'Weekend hire');

      final captured = verify(() => incomeRecordRepository.recordIncome(captureAny())).captured;
      final draft = captured.single as IncomeRecordDraft;
      expect(draft.locationId, 'loc-1');
      expect(draft.source, 'Equipment rental');
      expect(draft.notes, 'Weekend hire');
    });
  });

  group('getAvailableBalance', () {
    test('nets every inflow against every outflow, all-time', () async {
      final balance = await repository.getAvailableBalance();
      // 1350 in - 400 out
      expect(balance, 950);
    });
  });

  group('cash drawer', () {
    test('getActiveDrawerSession returns null when nothing is open', () async {
      when(() => cashDrawerShiftRepository.getActiveShift(locationId: 'loc-1'))
          .thenAnswer((_) async => null);

      expect(await repository.getActiveDrawerSession(), isNull);
    });

    test('getActiveDrawerSession maps an open shift', () async {
      when(() => cashDrawerShiftRepository.getActiveShift(locationId: 'loc-1')).thenAnswer(
        (_) async => CashDrawerShift(
          localId: 'shift-1',
          cashierUserId: 'user-1',
          locationId: 'loc-1',
          openedAt: DateTime(2026, 7, 20, 8),
          openingCash: 5000,
        ),
      );

      final session = await repository.getActiveDrawerSession();
      expect(session!.openingFloat, 5000);
      expect(session.openedAt, DateTime(2026, 7, 20, 8));
    });

    test('computeExpectedCash throws when no drawer is open', () async {
      when(() => cashDrawerShiftRepository.getActiveShift(locationId: 'loc-1'))
          .thenAnswer((_) async => null);

      await expectLater(repository.computeExpectedCash(), throwsA(isA<StateError>()));
    });

    test('closeDrawer builds salesByMethod/expensesTotal from the since-open feed and '
        'delegates the actual close', () async {
      final shift = CashDrawerShift(
        localId: 'shift-1',
        cashierUserId: 'user-1',
        locationId: 'loc-1',
        openedAt: DateTime(2026, 7, 20, 8),
        openingCash: 5000,
      );
      when(() => cashDrawerShiftRepository.getActiveShift(locationId: 'loc-1'))
          .thenAnswer((_) async => shift);
      when(() => cashDrawerShiftRepository.computeExpectedCash('shift-1')).thenAnswer(
        (_) async => const ExpectedCashPreview(
          openingCash: 5000,
          cashSales: 1000,
          cashExpenses: 300,
          expectedCash: 5700,
        ),
      );
      when(() => cashDrawerShiftRepository.closeShift(
            shiftLocalId: any(named: 'shiftLocalId'),
            closingCash: any(named: 'closingCash'),
            notes: any(named: 'notes'),
          )).thenAnswer(
        (_) async => CashDrawerShift(
          localId: 'shift-1',
          cashierUserId: 'user-1',
          locationId: 'loc-1',
          openedAt: shift.openedAt,
          openingCash: 5000,
          closedAt: DateTime(2026, 7, 20, 18),
          closingCash: 5650,
        ),
      );

      final summary = await repository.closeDrawer(countedCash: 5650, note: 'End of day');

      expect(summary.expectedCash, 5700);
      expect(summary.countedCash, 5650);
      expect(summary.salesByMethod['Cash'], 1000);
      expect(summary.expensesTotal, 400); // 300 expense + 100 supplier payment
      expect(summary.netForDay, 600); // 1000 sales - 400 out
      verify(() => cashDrawerShiftRepository.closeShift(
            shiftLocalId: 'shift-1',
            closingCash: 5650,
            notes: 'End of day',
          )).called(1);
    });
  });
}
