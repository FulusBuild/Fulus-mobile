/// Volume 8 (Finance)'s Cash Flow feed, modeled as one unified ledger.
///
/// **Integration status, CORRECTED**: [MoneyTransaction] and everything
/// under `features/money/data/` now back the Cash Flow screen,
/// transaction history, transaction detail, Add Income, Add Expense,
/// and Daily Closing with real data. This used to read: every one of
/// those is location-scoped in the real domain (`SaleRepository`,
/// `ExpenseRepository`, `IncomeRecordRepository`,
/// `CashDrawerShiftRepository` all require a `locationId`), and nothing
/// anywhere in this app yet resolves which location a device is at —
/// so this feature built against its own small `MoneyRepository` seam
/// instead of those real repositories, backed by mock data. That gap is
/// closed now: `domain/usecases/active_location_resolver.dart`'s
/// `ResolveActiveLocation` is the resolution mechanism that was
/// missing, and `RealMoneyRepositoryImpl`
/// (`features/money/data/real_money_repository.dart`) is the real
/// `MoneyRepository` implementation this comment used to say should
/// exist "once a location is resolvable" — exactly as predicted, the
/// screens themselves needed no changes, only which implementation
/// `moneyRepositoryProvider` returns (`money_providers.dart`).
/// `MockMoneyRepository` still exists but nothing constructs it
/// anymore.
///
/// `RealMoneyRepositoryImpl` deliberately does not read from
/// `FinanceStatsRepository` — see that class's own doc comment for the
/// specific under-reporting gap in `FinanceStatsRepositoryImpl.
/// getCashFlow` that made delegating to it the wrong choice here.
///
/// Customers (Credit Book) and Suppliers (Pay Supplier) were always the
/// business-wide, no-locationId-needed case — `CustomerRepository`/
/// `CustomerCreditRepository`/`SupplierRepository`/
/// `SupplierCreditRepository` were already fully implemented and wired
/// directly to the real repositories before this pass, not mocked. See
/// `customers_list_screen.dart` and `suppliers_list_screen.dart`.
library;

enum MoneyTransactionType {
  /// A completed sale — the till ringing. Mirrors `Sale`.
  saleIncome,

  /// Money in that wasn't a sale — Volume 8's "Add Income" action.
  manualIncome,

  /// A credit customer paying down what they owe — mirrors
  /// `CustomerLedgerEntryType.repayment`.
  customerRepayment,

  /// Volume 8's "Add Expense" action. Mirrors `Expense`.
  expense,

  /// Paying down what the business owes a supplier — mirrors
  /// `SupplierLedgerEntryType.paymentMade`.
  supplierPayment;

  /// "Money In, Money Out" — Volume 8's own two-bucket framing.
  bool get isInflow =>
      this == MoneyTransactionType.saleIncome ||
      this == MoneyTransactionType.manualIncome ||
      this == MoneyTransactionType.customerRepayment;
}

/// One row in the unified Cash Flow feed. [amount] is always the
/// positive, raw magnitude — direction comes from [type], the same
/// convention `CustomerLedgerEntry.amount`/`SupplierLedgerEntry.amount`
/// already use elsewhere in this codebase.
class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.dateTime,
    this.subtitle,
    this.category,
    this.paymentMethod,
    this.counterpartyName,
    this.reference,
    this.note,
    this.lineItems,
    this.receiptPhotoPath,
  });

  final String id;
  final MoneyTransactionType type;

  /// e.g. "Sale — INV-2041", "Rent", "Payment from Ngozi Books".
  final String title;

  /// e.g. a category ("Rent"), a short items summary ("3 items"), or a
  /// customer/supplier name — shown under [title] on a list row.
  final String? subtitle;

  final double amount;
  final DateTime dateTime;

  /// Expense category ("Rent", "Transport", "Wages", "Utilities",
  /// "Other") — only set for [MoneyTransactionType.expense].
  final String? category;

  /// "Cash" / "Mobile Money" / "Bank Transfer" / "Card".
  final String? paymentMethod;

  /// Customer or supplier name, when relevant.
  final String? counterpartyName;

  /// A receipt/invoice number, when relevant.
  final String? reference;

  final String? note;

  /// Line items for a [MoneyTransactionType.saleIncome] row, e.g.
  /// "2 × Bag of Rice — ₦9,000" — shown on the transaction detail
  /// screen only, never on a list row.
  final List<String>? lineItems;

  /// A local file path to a photographed receipt — only ever set for
  /// [MoneyTransactionType.expense] (see `Expense.receiptPhotoPath`'s
  /// own doc comment). Gap-closure pass: "Receipt photo attachment on
  /// expenses."
  final String? receiptPhotoPath;

  bool get isInflow => type.isInflow;

  /// Signed amount — positive for money in, negative for money out.
  /// Used when summing a list of transactions into a net figure.
  double get signedAmount => isInflow ? amount : -amount;
}
