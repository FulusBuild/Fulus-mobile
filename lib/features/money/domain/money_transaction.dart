/// Volume 8 (Finance)'s Cash Flow feed, modeled as one unified ledger.
///
/// **Integration status**: [MoneyTransaction] and everything under
/// `features/money/data/` back the Cash Flow screen, transaction
/// history, transaction detail, Add Income, Add Expense, and Daily
/// Closing — every one of those is location-scoped in the real domain
/// (`SaleRepository`, `ExpenseRepository`, `IncomeRecordRepository`,
/// `FinanceStatsRepository`, `CashDrawerShiftRepository` all require a
/// `locationId`), and nothing anywhere in this app yet resolves which
/// location a device is at (`LocationRepository.watchLocations()` has
/// no call site — confirmed by grep — because Locations are
/// desktop-managed, Architecture Section 7a, and no location-switcher
/// UI exists). So this feature builds against its own small
/// `MoneyRepository` seam instead of those real repositories, backed by
/// realistic mock data, exactly per this task's own "use mock data
/// where backend data isn't yet available" instruction. Once a location
/// is resolvable, a real `MoneyRepository` implementation should read
/// from the five repositories named above and this mock one retires —
/// the screens themselves don't need to change, only which
/// implementation `moneyRepositoryProvider` returns.
///
/// Customers (Credit Book) and Suppliers (Pay Supplier) are the
/// opposite case — `CustomerRepository`/`CustomerCreditRepository`/
/// `SupplierRepository`/`SupplierCreditRepository` are business-wide,
/// need no locationId, and are fully implemented already — so those
/// parts of Money are wired directly to the real repositories, not
/// mocked. See `customers_list_screen.dart` and `suppliers_list_screen
/// .dart`.
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

  bool get isInflow => type.isInflow;

  /// Signed amount — positive for money in, negative for money out.
  /// Used when summing a list of transactions into a net figure.
  double get signedAmount => isInflow ? amount : -amount;
}
