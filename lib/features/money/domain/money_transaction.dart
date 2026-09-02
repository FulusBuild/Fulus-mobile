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
    this.paymentBreakdown,
    this.cashierName,
    this.saleTotal,
    this.counterpartyPhone,
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

  /// Feature (transaction audit center): the customer's phone number,
  /// alongside [counterpartyName] — same "only ever resolved for the
  /// single-transaction detail view" cost tradeoff as [cashierName].
  /// Only meaningful for a sale with a customer attached; null
  /// otherwise (no customer, or a non-sale transaction type — a
  /// supplier's own [counterpartyName] never gets a phone lookup here,
  /// since nothing asked for one).
  final String? counterpartyPhone;

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

  /// Bug fix: the individual legs behind a *split* payment — e.g. a
  /// sale paid "Credit ₦50,000 + Mobile Money ₦197,250" used to be
  /// reduced down to just [paymentMethod] == "Split" everywhere,
  /// including the detail screen, with the actual breakdown thrown
  /// away after `Sale.paymentMethod` was computed. `method` is already
  /// display-formatted (`RealMoneyRepositoryImpl._displayPaymentMethod`
  /// — the same helper [paymentMethod] itself is built from); `amount`
  /// is left raw for the presentation layer to format with whatever
  /// currency symbol it already has on hand, the same division of
  /// responsibility [amount] above already follows. Only ever populated
  /// for the single-transaction detail view (same "detail screen only,
  /// never a list row" cost tradeoff [lineItems] documents above) —
  /// null for every non-split sale and for every other transaction
  /// type.
  final List<({String method, double amount})>? paymentBreakdown;

  /// Feature (transaction audit center): who rang this up — a
  /// `Sales.cashierUserId` lookup, only ever resolved for the
  /// single-transaction detail view (same cost tradeoff as
  /// [paymentBreakdown] and the name-resolved [lineItems] above). Null
  /// for a sale made before that column existed, one with nobody
  /// signed in, or any non-sale transaction type.
  final String? cashierName;

  /// Feature (transaction audit center): the sale's actual total,
  /// distinct from [amount] (which is `Sale.amountPaid` — see this
  /// class's own doc comment on why: cash-basis, not accrual). Without
  /// this there's no way to show "Total / Paid / Balance Due" as three
  /// distinct figures — [amount] alone can't tell a partially-paid sale
  /// apart from a smaller sale that was paid in full. Null for any
  /// non-sale transaction type, where "total vs. paid" isn't a
  /// distinct concept in the first place.
  final double? saleTotal;

  /// `saleTotal - amount`, floored at 0 — mirrors `Sale.balanceDue`/
  /// `ReceiptData.balanceDue` exactly. Always 0 when [saleTotal] is
  /// null (a non-sale row, or a sale row from before detail-enrichment
  /// populated it).
  double get balanceDue {
    final total = saleTotal;
    if (total == null) return 0;
    final due = total - amount;
    return due > 0 ? due : 0;
  }

  /// paid | partial | unpaid — derived the same way
  /// `ReceiptRepositoryImpl._derivePaymentStatus` derives it for a
  /// receipt, so the two never disagree about the same sale. Always
  /// "paid" when [saleTotal] is null, since every non-sale
  /// [MoneyTransaction] (an expense, a manual income entry, a
  /// repayment) is, by construction, never partially recorded.
  String get paymentStatus {
    final total = saleTotal;
    if (total == null || total <= 0) return 'paid';
    if (amount <= 0) return 'unpaid';
    if (amount >= total) return 'paid';
    return 'partial';
  }

  bool get isInflow => type.isInflow;

  /// Signed amount — positive for money in, negative for money out.
  /// Used when summing a list of transactions into a net figure.
  double get signedAmount => isInflow ? amount : -amount;
}
