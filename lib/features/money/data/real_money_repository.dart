import '../../../domain/entities/cash_drawer_shift.dart';
import '../../../domain/entities/customer_ledger_entry.dart';
import '../../../domain/entities/expense.dart';
import '../../../domain/entities/expense_category.dart';
import '../../../domain/entities/income_record.dart';
import '../../../domain/entities/report.dart';
import '../../../domain/entities/sale.dart';
import '../../../domain/entities/supplier_ledger_entry.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/repositories/cash_drawer_shift_repository.dart';
import '../../../domain/repositories/customer_credit_repository.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/expense_category_repository.dart';
import '../../../domain/repositories/expense_repository.dart';
import '../../../domain/repositories/income_record_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../../domain/repositories/sale_repository.dart';
import '../../../domain/repositories/supplier_credit_repository.dart';
import '../../../domain/repositories/supplier_repository.dart';
import '../../../domain/usecases/active_location_resolver.dart';
import '../domain/cash_drawer_state.dart';
import '../domain/money_summary.dart';
import '../domain/money_transaction.dart';
import 'money_repository.dart';

/// The real [MoneyRepository] — closes the gap `money_transaction.dart`'s
/// own doc comment named ("nothing anywhere in this app yet resolves
/// which location a device is at"). Now that
/// [ResolveActiveLocation] exists, this class reads directly from
/// [SaleRepository]/[ExpenseRepository]/[IncomeRecordRepository]/
/// [CustomerCreditRepository]/[SupplierCreditRepository]/
/// [CashDrawerShiftRepository] instead of `MockMoneyRepository`'s
/// generated data. The screens themselves needed no changes — see
/// `money_providers.dart`'s `moneyRepositoryProvider` for the one line
/// that actually switches implementations.
///
/// Deliberately does **not** read from `FinanceStatsRepository`, despite
/// `money_transaction.dart`'s own doc comment naming it as one of "the
/// five repositories" a real implementation should read from: a close
/// read of `FinanceStatsRepositoryImpl.getCashFlow` found its `inflow`
/// total only ever sums `salesInflow + manualIncomeInflow` — customer
/// repayments never enter it. Volume 8 is explicit that "Money In
/// includes sales income, manual income, AND customer repayments";
/// delegating to that method would have silently under-reported Money
/// In by every repayment in the period, a real regression against what
/// `MockMoneyRepository` already got right. That gap belongs to
/// Reports/Finance and is out of scope for a Location ID task to fix
/// silently as a side effect of an unrelated change — so this class
/// builds its own aggregation directly from the other five repositories
/// money_transaction.dart named, all independently correct.
///
/// Customer repayments and supplier payments are intentionally
/// business-wide in every method below, never filtered by the active
/// location — `CustomerLedgerEntries`/`SupplierLedgerEntries` have no
/// `locationId` column (tables.dart) and Customers/Suppliers aren't
/// location-scoped either. That's an existing, deliberate architectural
/// fact this class preserves, not a gap this pass introduced or should
/// silently "fix" by inventing a filter the data can't support.
class RealMoneyRepositoryImpl implements MoneyRepository {
  RealMoneyRepositoryImpl({
    required SaleRepository saleRepository,
    required ExpenseRepository expenseRepository,
    required IncomeRecordRepository incomeRecordRepository,
    required CustomerCreditRepository customerCreditRepository,
    required SupplierCreditRepository supplierCreditRepository,
    required CashDrawerShiftRepository cashDrawerShiftRepository,
    required ExpenseCategoryRepository expenseCategoryRepository,
    required CustomerRepository customerRepository,
    required SupplierRepository supplierRepository,
    required ProductRepository productRepository,
    required AuthRepository authRepository,
    required ResolveActiveLocation resolveActiveLocation,
  })  : _saleRepository = saleRepository,
        _expenseRepository = expenseRepository,
        _incomeRecordRepository = incomeRecordRepository,
        _customerCreditRepository = customerCreditRepository,
        _supplierCreditRepository = supplierCreditRepository,
        _cashDrawerShiftRepository = cashDrawerShiftRepository,
        _expenseCategoryRepository = expenseCategoryRepository,
        _customerRepository = customerRepository,
        _supplierRepository = supplierRepository,
        _productRepository = productRepository,
        _authRepository = authRepository,
        _resolveActiveLocation = resolveActiveLocation;

  final SaleRepository _saleRepository;
  final ExpenseRepository _expenseRepository;
  final IncomeRecordRepository _incomeRecordRepository;
  final CustomerCreditRepository _customerCreditRepository;
  final SupplierCreditRepository _supplierCreditRepository;
  final CashDrawerShiftRepository _cashDrawerShiftRepository;
  final ExpenseCategoryRepository _expenseCategoryRepository;
  final CustomerRepository _customerRepository;
  final SupplierRepository _supplierRepository;
  final ProductRepository _productRepository;
  final AuthRepository _authRepository;
  final ResolveActiveLocation _resolveActiveLocation;

  /// Wide enough to include everything a real business could have
  /// recorded — [getAvailableBalance] is the one method genuinely
  /// "all-time" rather than period-scoped (matching
  /// `MockMoneyRepository.getAvailableBalance`'s own full-history sum),
  /// and every underlying repository method needs an explicit
  /// start/end rather than supporting an open-ended query.
  static final DateTime _epoch = DateTime(2000, 1, 1);

  Future<String> get _locationId => _resolveActiveLocation.call();

  // ── Building the unified transaction feed ─────────────────────────

  /// The real-data equivalent of `MockMoneyRepository`'s in-memory
  /// `_transactions` list — built fresh from all five real repositories
  /// on every call rather than cached, since Drift's own query engine
  /// (not this class) is this app's caching layer.
  /// Employee data isolation: [cashierUserId] scopes the *sales* portion
  /// of this range to one cashier when given (default: everyone's,
  /// unchanged for every existing caller). Expenses, income records, and
  /// repayments aren't included in that scoping — none of those
  /// entities carry a "recorded by" user field in the current schema, so
  /// there's nothing to filter them by; they remain business-wide
  /// regardless of who's asking. [getSummary]/[getTransactions] are the
  /// only callers that ever pass this; the cash-drawer reconciliation
  /// call below (`computeExpectedCash`/`closeDrawer`'s "sinceOpen") is
  /// deliberately left unscoped — a shared drawer's expected cash has to
  /// include every sale that went through it, not just one cashier's,
  /// or the reconciliation math comes out wrong.
  Future<List<MoneyTransaction>> _transactionsForRange(
    DateTime start,
    DateTime end, {
    String? cashierUserId,
  }) async {
    final locationId = await _locationId;

    final sales = await _saleRepository.getSalesForPeriod(
      locationId: locationId,
      start: start,
      end: end,
      cashierUserId: cashierUserId,
    );
    // Employee data isolation: none of these four carry a "recorded by"
    // user field (checked — no schema support for it today), so there's
    // no correct way to scope them to one cashier. Skipped entirely
    // rather than shown unscoped: showing every expense/income/
    // repayment/supplier-payment the whole business ever recorded to a
    // cashier who's only supposed to see their own sales would defeat
    // the actual point of this scoping, even if each individual row
    // can't be pinned on anyone in particular.
    final expenses = cashierUserId != null
        ? const <Expense>[]
        : await _expenseRepository.getExpensesForPeriod(locationId: locationId, start: start, end: end);
    final incomeRecords = cashierUserId != null
        ? const <IncomeRecord>[]
        : await _incomeRecordRepository.getIncomeRecordsForPeriod(locationId: locationId, start: start, end: end);
    final repayments = cashierUserId != null
        ? const <CustomerLedgerEntry>[]
        : await _customerCreditRepository.getRepaymentsForPeriod(start: start, end: end);
    final payments = cashierUserId != null
        ? const <SupplierLedgerEntry>[]
        : await _supplierCreditRepository.getPaymentsForPeriod(start: start, end: end);

    // Resolved once per call, not once per row — watchExpenseCategories
    // is already a reactive Stream elsewhere in the app; `.first` here
    // is the same one-shot-snapshot idiom SellScreen/
    // ImportProductsFromCsv already use to read a reactive source from
    // a Future-based context.
    final categories = await _expenseCategoryRepository.watchExpenseCategories().first;
    final categoryNamesById = {for (final c in categories) c.localId: c.name};

    // Bug fix (Receipt History gap-closure): `_fromSale` used to never
    // resolve a sale's customer name at all — only `_fromSaleDetailed`
    // did, via its own per-sale `getCustomerById` lookup, deliberately
    // left list-path-only because doing that per sale here would be
    // exactly the N+1-across-a-date-range cost that method's own doc
    // comment already avoids for line items/payment breakdown. Customers
    // is a small, business-wide table — same cost tradeoff already made
    // for categoryNamesById just above, not a new N+1 — so one bulk read
    // here is enough for a list row to show "who this sale was for"
    // without paying a per-row lookup.
    final customers = await _customerRepository.watchCustomers().first;
    final customerNamesById = {for (final c in customers) c.localId: c.name};

    final transactions = <MoneyTransaction>[
      for (final sale in sales) _fromSale(sale, customerNamesById),
      for (final expense in expenses) _fromExpense(expense, categoryNamesById),
      for (final income in incomeRecords) _fromIncomeRecord(income),
    ];
    for (final entry in repayments) {
      transactions.add(await _fromRepayment(entry));
    }
    for (final entry in payments) {
      transactions.add(await _fromPayment(entry));
    }

    transactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return transactions;
  }

  MoneyTransaction _fromSale(Sale sale, Map<String, String> customerNamesById) {
    // Cash-basis, not accrual: amountPaid (what actually changed hands
    // at sale time), not total (what's owed). Same treatment
    // CashDrawerShiftRepositoryImpl.computeExpectedCash already gives
    // it (`cashSales += sale.amountPaid`) — using `total` here instead
    // would double-count the unpaid portion the moment a credit
    // customer's later repayment also appears as its own
    // customerRepayment transaction.
    final descriptiveItems = sale.items.where((i) => i.description.isNotEmpty).toList();
    return MoneyTransaction(
      id: 'sale-${sale.localId}',
      type: MoneyTransactionType.saleIncome,
      title: sale.invoiceNumber != null ? 'Sale — ${sale.invoiceNumber}' : 'Sale',
      subtitle: '${sale.items.length} item${sale.items.length == 1 ? '' : 's'}',
      amount: sale.amountPaid,
      dateTime: sale.saleDate,
      paymentMethod: _displayPaymentMethod(sale.paymentMethod),
      // Bug fix (Receipt History gap-closure): resolved from the bulk
      // [customerNamesById] map built once per call — see
      // `_transactionsForRange`'s own comment just above where that map
      // is built. Null for a walk-in sale with no customer attached, the
      // same as every other field here that's simply absent rather than
      // fabricated.
      counterpartyName: sale.customerId != null ? customerNamesById[sale.customerId] : null,
      reference: sale.invoiceNumber,
      note: sale.notes,
      // Only populated from Quick Sale lines (the only SaleItem rows
      // with a real description) — a catalog product line's item name
      // lives on Product, not SaleItem, and resolving it would need a
      // ProductRepository lookup per line across every sale in range.
      // Left null rather than shown with a placeholder like "Item"
      // when nothing descriptive is available, matching this class's
      // own "don't fabricate what isn't really known" standard.
      lineItems: descriptiveItems.isEmpty
          ? null
          : [for (final item in descriptiveItems) '${item.quantity} × ${item.description}'],
      // Feature (transaction audit center): free to include even on the
      // fast list path — sale.total is already loaded, no extra query
      // needed, unlike lineItems/paymentBreakdown's detail-only cost.
      saleTotal: sale.total,
    );
  }

  /// Bug fix (business-logic audit): the detail-screen version of
  /// [_fromSale]. Two gaps that method's own comments named but
  /// deliberately left unfixed there because it also backs the Cash
  /// Flow *list* (N+1 product/payment lookups across every sale in a
  /// date range) don't apply here — `getTransactionById` resolves
  /// exactly one sale, so both are worth doing:
  ///
  /// 1. Catalog line items (the ordinary case — Quick Sale is the
  ///    exception) resolve their real product name via
  ///    [ProductRepository] instead of being silently omitted, so
  ///    "Items" shows real names for a normal sale, not just a Quick
  ///    Sale's raw typed description (or nothing at all).
  /// 2. A split-payment sale fetches its actual [SalePayment] legs and
  ///    exposes them via [MoneyTransaction.paymentBreakdown], instead
  ///    of only the collapsed "Split" label.
  Future<MoneyTransaction> _fromSaleDetailed(Sale sale) async {
    // Empty map, deliberately: `base.counterpartyName` below is only
    // ever used as a fallback for the (rare) case a customerId doesn't
    // resolve; the real resolution for this detail path is the direct
    // `getCustomerById` lookup a few lines down, which needs no bulk map
    // at all for a single sale.
    final base = _fromSale(sale, const <String, String>{});

    final resolvedLineItems = <String>[];
    for (final item in sale.items) {
      if (item.description.isNotEmpty) {
        resolvedLineItems.add('${item.quantity} × ${item.description}');
        continue;
      }
      final productLocalId = item.productLocalId;
      if (productLocalId == null) continue;
      final product = await _productRepository.getProductById(productLocalId, locationId: sale.locationId);
      resolvedLineItems.add('${item.quantity} × ${product?.product.name ?? 'Unknown item'}');
    }

    List<({String method, double amount})>? paymentBreakdown;
    if (sale.paymentMethod == 'split') {
      final legs = await _saleRepository.getPaymentsForSale(sale.localId);
      if (legs.isNotEmpty) {
        paymentBreakdown = [
          for (final leg in legs) (method: _displayPaymentMethod(leg.method) ?? leg.method, amount: leg.amount),
        ];
      }
    }

    // Feature (transaction audit center): customer name+phone. `_fromSale`
    // now resolves a customer *name* for the list feed too (Receipt
    // History gap-closure — see that method's own comment), but only
    // from a bulk-loaded map with no phone number attached; this is
    // still the only place a sale's customer *phone* is looked up, and
    // it re-resolves the name directly via `getCustomerById` rather than
    // trusting `base.counterpartyName`, so a customer renamed after this
    // call's own bulk read is never stale on the one screen that matters
    // most for a single transaction.
    String? customerName = base.counterpartyName;
    String? customerPhone;
    if (sale.customerId != null) {
      final customer = await _customerRepository.getCustomerById(sale.customerId!);
      customerName = customer?.name;
      customerPhone = customer?.phone;
    }

    // Feature (transaction audit center): cashier name. listLocalIdentities
    // returns every local identity on the device — deliberately small
    // (AuthRepository's own doc comment: "a handful of local accounts at
    // most") — rather than a single-user lookup that doesn't exist on
    // this interface.
    String? cashierName;
    if (sale.cashierUserId != null) {
      final identities = await _authRepository.listLocalIdentities();
      for (final identity in identities) {
        if (identity.id == sale.cashierUserId) {
          cashierName = identity.fullName;
          break;
        }
      }
    }

    return MoneyTransaction(
      id: base.id,
      type: base.type,
      title: base.title,
      subtitle: base.subtitle,
      amount: base.amount,
      dateTime: base.dateTime,
      category: base.category,
      paymentMethod: base.paymentMethod,
      counterpartyName: customerName,
      counterpartyPhone: customerPhone,
      reference: base.reference,
      note: base.note,
      lineItems: resolvedLineItems.isEmpty ? null : resolvedLineItems,
      receiptPhotoPath: base.receiptPhotoPath,
      paymentBreakdown: paymentBreakdown,
      saleTotal: base.saleTotal,
      cashierName: cashierName,
    );
  }

  MoneyTransaction _fromExpense(Expense expense, Map<String, String> categoryNamesById) {
    final categoryName = expense.categoryId != null
        ? categoryNamesById[expense.categoryId] ?? 'Other'
        : 'Other';
    return MoneyTransaction(
      id: 'expense-${expense.localId}',
      type: MoneyTransactionType.expense,
      title: expense.description,
      subtitle: categoryName,
      category: categoryName,
      amount: expense.amount,
      dateTime: expense.expenseDate,
      paymentMethod: _displayPaymentMethod(expense.paymentMethod),
      receiptPhotoPath: expense.receiptPhotoPath,
    );
  }

  MoneyTransaction _fromIncomeRecord(IncomeRecord income) {
    return MoneyTransaction(
      id: 'income-${income.localId}',
      type: MoneyTransactionType.manualIncome,
      title: income.source,
      subtitle: 'Other income',
      amount: income.amount,
      dateTime: income.incomeDate,
      note: income.notes,
    );
  }

  Future<MoneyTransaction> _fromRepayment(CustomerLedgerEntry entry) async {
    final customer = await _customerRepository.getCustomerById(entry.customerLocalId);
    final name = customer?.name ?? 'Customer';
    return MoneyTransaction(
      id: 'repayment-${entry.localId}',
      type: MoneyTransactionType.customerRepayment,
      title: 'Payment from $name',
      subtitle: name,
      amount: entry.amount,
      dateTime: entry.createdAt,
      paymentMethod: _displayPaymentMethod(entry.paymentMethod),
      counterpartyName: customer?.name,
      note: entry.note,
    );
  }

  Future<MoneyTransaction> _fromPayment(SupplierLedgerEntry entry) async {
    final supplier = await _supplierRepository.getSupplierById(entry.supplierLocalId);
    final name = supplier?.name ?? 'Supplier';
    return MoneyTransaction(
      id: 'payment-${entry.localId}',
      type: MoneyTransactionType.supplierPayment,
      title: 'Payment to $name',
      subtitle: name,
      amount: entry.amount,
      dateTime: entry.createdAt,
      paymentMethod: _displayPaymentMethod(entry.paymentMethod),
      counterpartyName: supplier?.name,
      note: entry.note,
    );
  }

  /// 'cash'/'mobile_money'/'card' (Sell's own checkout keys,
  /// payment_screen.dart) -> "Cash"/"Mobile Money"/"Card" (Sell's own
  /// display labels for those same keys) — so a Sale-sourced
  /// transaction and an Expense-sourced one display identically for
  /// the same underlying method, and neither ever shows a raw
  /// snake_case string in the UI.
  String? _displayPaymentMethod(String? storageKey) {
    if (storageKey == null) return null;
    switch (storageKey) {
      case 'cash':
        return 'Cash';
      case 'mobile_money':
        return 'Mobile Money';
      case 'card':
        return 'Card';
      default:
        // Unrecognized key (shouldn't normally arise) — title-case it
        // rather than showing a raw string.
        return storageKey
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  /// The inverse of [_displayPaymentMethod] — normalizes whatever
  /// label the Add Expense screen collected ("Cash", "Mobile Money",
  /// or "Bank/Card" — `_kExpensePaymentMethods`,
  /// add_expense_screen.dart) into the same lowercase keys Sell's
  /// checkout already writes into `Sale.paymentMethod`. This matters
  /// beyond display consistency: CashDrawerShiftRepositoryImpl.
  /// computeExpectedCash queries `Expenses` directly with
  /// `e.paymentMethod.equals('cash')` — storing the raw "Cash" label
  /// unnormalized would silently make every expense recorded through
  /// this real Money repository invisible to that existing cash-
  /// reconciliation query. "Bank/Card" maps to 'card' specifically
  /// (not a new key) so it's excluded from cash calculations exactly
  /// like Sell's own 'card' payments already are, reusing the
  /// vocabulary rather than fragmenting it further.
  String _toStorageKey(String displayLabel) {
    switch (displayLabel) {
      case 'Cash':
        return 'cash';
      case 'Mobile Money':
        return 'mobile_money';
      case 'Card':
      case 'Bank/Card':
        return 'card';
      default:
        return displayLabel.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    }
  }

  /// Get-or-create by name — Add Expense's category options
  /// (`_kExpenseCategories`) are fixed UI strings, not necessarily
  /// pre-existing `ExpenseCategory` rows, so a real `Expense.categoryId`
  /// needs a matching row to point at before it can be written.
  Future<String> _resolveExpenseCategoryId(String categoryName) async {
    final categories = await _expenseCategoryRepository.watchExpenseCategories().first;
    for (final c in categories) {
      if (c.name.toLowerCase() == categoryName.toLowerCase()) return c.localId;
    }
    final created = await _expenseCategoryRepository.createExpenseCategory(
      ExpenseCategoryDraft(name: categoryName),
    );
    return created.localId;
  }

  List<CategoryTotal> _breakdownIncome(List<MoneyTransaction> inPeriod) {
    final rows = <CategoryTotal>[];
    void addBucket(String label, MoneyTransactionType type) {
      final matches = inPeriod.where((t) => t.type == type).toList();
      if (matches.isEmpty) return;
      rows.add(CategoryTotal(
        label: label,
        amount: matches.fold<double>(0, (sum, t) => sum + t.amount),
        count: matches.length,
        type: type,
      ));
    }

    addBucket('Sales income', MoneyTransactionType.saleIncome);
    addBucket('Customer repayments', MoneyTransactionType.customerRepayment);
    addBucket('Other income', MoneyTransactionType.manualIncome);
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  List<CategoryTotal> _breakdownExpense(List<MoneyTransaction> inPeriod) {
    final byCategory = <String, List<MoneyTransaction>>{};
    for (final t in inPeriod.where((t) => t.type == MoneyTransactionType.expense)) {
      byCategory.putIfAbsent(t.category ?? 'Other', () => []).add(t);
    }
    final rows = [
      for (final entry in byCategory.entries)
        CategoryTotal(
          label: entry.key,
          amount: entry.value.fold<double>(0, (sum, t) => sum + t.amount),
          count: entry.value.length,
          type: MoneyTransactionType.expense,
        ),
    ];
    final supplierPayments =
        inPeriod.where((t) => t.type == MoneyTransactionType.supplierPayment).toList();
    if (supplierPayments.isNotEmpty) {
      rows.add(CategoryTotal(
        label: 'Supplier payments',
        amount: supplierPayments.fold<double>(0, (sum, t) => sum + t.amount),
        count: supplierPayments.length,
        type: MoneyTransactionType.supplierPayment,
      ));
    }
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  // ── MoneyRepository ────────────────────────────────────────────────

  @override
  Future<double> getAvailableBalance() async {
    final transactions = await _transactionsForRange(_epoch, DateTime.now());
    return transactions.fold<double>(0, (sum, t) => sum + t.signedAmount);
  }

  @override
  Future<MoneySummary> getSummary(
    ReportPeriod period, {
    required String currentAuthUserId,
    required bool canViewAllSales,
  }) async {
    final cashierUserId = canViewAllSales ? null : currentAuthUserId;
    final inPeriod = await _transactionsForRange(period.start, period.end, cashierUserId: cashierUserId);

    double sumWhere(bool Function(MoneyTransaction) test) =>
        inPeriod.where(test).fold<double>(0, (sum, t) => sum + t.amount);

    final moneyIn = sumWhere((t) => t.isInflow);
    final moneyOut = sumWhere((t) => !t.isInflow);

    final previousPeriod = period.previous;
    final previousTransactions = await _transactionsForRange(
      previousPeriod.start,
      previousPeriod.end,
      cashierUserId: cashierUserId,
    );
    final previousNet =
        previousTransactions.fold<double>(0, (sum, t) => sum + t.signedAmount);

    return MoneySummary(
      period: period,
      moneyIn: moneyIn,
      moneyOut: moneyOut,
      previousNet: previousNet,
      incomeBreakdown: _breakdownIncome(inPeriod),
      expenseBreakdown: _breakdownExpense(inPeriod),
      transactionCount: inPeriod.length,
    );
  }

  @override
  Future<List<MoneyTransaction>> getTransactions(
    ReportPeriod period, {
    required String currentAuthUserId,
    required bool canViewAllSales,
    MoneyTransactionType? typeFilter,
    String? category,
    String? searchQuery,
  }) async {
    final cashierUserId = canViewAllSales ? null : currentAuthUserId;
    final inPeriod = await _transactionsForRange(period.start, period.end, cashierUserId: cashierUserId);
    final query = searchQuery?.trim().toLowerCase();
    return inPeriod.where((t) {
      if (typeFilter != null && t.type != typeFilter) return false;
      if (category != null && t.category != category) return false;
      if (query != null && query.isNotEmpty) {
        final haystack = [t.title, t.subtitle, t.counterpartyName, t.reference]
            .where((s) => s != null)
            .map((s) => s!.toLowerCase())
            .join(' ');
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<MoneyTransaction?> getTransactionById(String id) async {
    if (id.startsWith('sale-')) {
      final sale = await _saleRepository.getSaleByLocalId(id.substring('sale-'.length));
      return sale == null ? null : _fromSaleDetailed(sale);
    }
    if (id.startsWith('expense-')) {
      final expense =
          await _expenseRepository.getExpenseById(id.substring('expense-'.length));
      if (expense == null) return null;
      final categories = await _expenseCategoryRepository.watchExpenseCategories().first;
      final categoryNamesById = {for (final c in categories) c.localId: c.name};
      return _fromExpense(expense, categoryNamesById);
    }
    if (id.startsWith('income-')) {
      final income =
          await _incomeRecordRepository.getIncomeRecordById(id.substring('income-'.length));
      return income == null ? null : _fromIncomeRecord(income);
    }
    if (id.startsWith('repayment-')) {
      // CustomerCreditRepository has no getById-equivalent — reusing
      // getRepaymentsForPeriod with a wide range rather than adding a
      // third new method to that repository for a single detail-screen
      // lookup, only ever reached from a user tapping into one specific
      // transaction, not a hot path.
      final localId = id.substring('repayment-'.length);
      final repayments =
          await _customerCreditRepository.getRepaymentsForPeriod(start: _epoch, end: DateTime.now());
      for (final entry in repayments) {
        if (entry.localId == localId) return _fromRepayment(entry);
      }
      return null;
    }
    if (id.startsWith('payment-')) {
      final localId = id.substring('payment-'.length);
      final payments =
          await _supplierCreditRepository.getPaymentsForPeriod(start: _epoch, end: DateTime.now());
      for (final entry in payments) {
        if (entry.localId == localId) return _fromPayment(entry);
      }
      return null;
    }
    return null;
  }

  @override
  Future<MoneyTransaction> recordIncome({
    required double amount,
    required String source,
    String? note,
  }) async {
    final locationId = await _locationId;
    final record = await _incomeRecordRepository.recordIncome(
      IncomeRecordDraft(
        locationId: locationId,
        source: source,
        amount: amount,
        incomeDate: DateTime.now(),
        notes: note,
      ),
    );
    return _fromIncomeRecord(record);
  }

  @override
  Future<MoneyTransaction> recordExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
    String? receiptPhotoPath,
  }) async {
    final locationId = await _locationId;
    final categoryId = await _resolveExpenseCategoryId(category);
    // Expense.description is required and this interface collects no
    // separate free-text field (Add Expense only offers category +
    // payment method + optional note) — the user's own note is the
    // more specific text when they gave one, falling back to the
    // category name (matching MockMoneyRepository.recordExpense's own
    // "use category for the title" simplification) when they didn't.
    final description = (note != null && note.trim().isNotEmpty) ? note.trim() : category;
    final expense = await _expenseRepository.recordExpense(
      ExpenseDraft(
        locationId: locationId,
        categoryId: categoryId,
        description: description,
        amount: amount,
        expenseDate: DateTime.now(),
        paymentMethod: _toStorageKey(paymentMethod),
        receiptPhotoPath: receiptPhotoPath,
      ),
    );
    final categories = await _expenseCategoryRepository.watchExpenseCategories().first;
    final categoryNamesById = {for (final c in categories) c.localId: c.name};
    return _fromExpense(expense, categoryNamesById);
  }

  @override
  Future<MoneyTransaction> attachReceiptPhoto({
    required String transactionId,
    required String? photoPath,
  }) async {
    if (!transactionId.startsWith('expense-')) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'Only an expense transaction can carry a receipt photo.',
      );
    }
    final localId = transactionId.substring('expense-'.length);
    await _expenseRepository.updateReceiptPhoto(localId: localId, photoPath: photoPath);
    final expense = await _expenseRepository.getExpenseById(localId);
    if (expense == null) {
      throw StateError('Expense $localId no longer exists.');
    }
    final categories = await _expenseCategoryRepository.watchExpenseCategories().first;
    final categoryNamesById = {for (final c in categories) c.localId: c.name};
    return _fromExpense(expense, categoryNamesById);
  }

  // ── Cash Drawer & Daily Closing ────────────────────────────────────

  @override
  Future<MoneyDrawerSession?> getActiveDrawerSession() async {
    final locationId = await _locationId;
    final shift = await _cashDrawerShiftRepository.getActiveShift(locationId: locationId);
    if (shift == null) return null;
    return MoneyDrawerSession(openingFloat: shift.openingCash, openedAt: shift.openedAt);
  }

  @override
  Future<MoneyDrawerSession> openDrawer({required double openingFloat}) async {
    final locationId = await _locationId;
    final shift = await _cashDrawerShiftRepository.openShift(
      CashDrawerShiftDraft(openingCash: openingFloat, locationId: locationId),
    );
    return MoneyDrawerSession(openingFloat: shift.openingCash, openedAt: shift.openedAt);
  }

  @override
  Future<MoneyExpectedCashPreview> computeExpectedCash() async {
    final locationId = await _locationId;
    final shift = await _cashDrawerShiftRepository.getActiveShift(locationId: locationId);
    if (shift == null) {
      throw StateError('No drawer is currently open.');
    }
    final preview = await _cashDrawerShiftRepository.computeExpectedCash(shift.localId);
    return MoneyExpectedCashPreview(
      openingFloat: preview.openingCash,
      cashSales: preview.cashSales,
      cashExpenses: preview.cashExpenses,
    );
  }

  @override
  Future<DailyClosingSummary> closeDrawer({
    required double countedCash,
    String? note,
  }) async {
    final locationId = await _locationId;
    final shift = await _cashDrawerShiftRepository.getActiveShift(locationId: locationId);
    if (shift == null) {
      throw StateError('No drawer is currently open.');
    }

    // Expected-cash figure: the server-mirroring cash-only computation
    // CashDrawerShiftRepositoryImpl already owns (Volume 8's "opening
    // float + cash sales - cash expenses" formula, verified directly
    // against the backend's own pos_service._compute_shift_totals).
    final preview = await _cashDrawerShiftRepository.computeExpectedCash(shift.localId);

    // salesByMethod/expensesTotal: MoneyRepository's own richer,
    // per-method summary shape, which CashDrawerShiftRepository has no
    // reason to provide (it only ever needed the cash-specific
    // figures above) — built from the same since-shift-open
    // transaction feed _transactionsForRange already knows how to
    // construct, the same way MockMoneyRepository derived its own
    // salesByMethod/expensesTotal from its in-memory transaction list
    // rather than a separate query.
    final sinceOpen = await _transactionsForRange(shift.openedAt, DateTime.now());
    final salesByMethod = <String, double>{};
    for (final t in sinceOpen.where((t) => t.type == MoneyTransactionType.saleIncome)) {
      final method = t.paymentMethod ?? 'Other';
      salesByMethod.update(method, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final expensesTotal = sinceOpen
        .where((t) =>
            t.type == MoneyTransactionType.expense ||
            t.type == MoneyTransactionType.supplierPayment)
        .fold<double>(0, (sum, t) => sum + t.amount);
    final totalSales = salesByMethod.values.fold<double>(0, (a, b) => a + b);

    // The actual close — CashDrawerShiftRepositoryImpl.closeShift's own
    // expectedCash/cashDifference computation and persistence,
    // independent of the salesByMethod/expensesTotal figures just
    // built above for display.
    final closedShift = await _cashDrawerShiftRepository.closeShift(
      shiftLocalId: shift.localId,
      closingCash: countedCash,
      notes: note,
    );

    return DailyClosingSummary(
      closedAt: closedShift.closedAt ?? DateTime.now(),
      salesByMethod: salesByMethod,
      expensesTotal: expensesTotal,
      netForDay: totalSales - expensesTotal,
      expectedCash: preview.expectedCash,
      countedCash: countedCash,
      note: note,
    );
  }
}
