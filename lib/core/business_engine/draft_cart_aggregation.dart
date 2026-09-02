/// Pure aggregation logic for turning a [DraftCart]'s local breakdown
/// into the single flat numbers `Sale`/`SaleCreateDto` actually need —
/// see tables.dart's `Sales.wholeCartDiscount`/`SalePayments` doc
/// comments for why the breakdown and the aggregate both need to exist.
library;

/// Combines Volume 5's two discount actions (whole-cart, per-line) into
/// the one number `Sale.discount`/the backend's `SaleCreate.discount`
/// actually is.
double combineDiscount({
  required double wholeCartDiscount,
  required List<double> lineDiscounts,
}) {
  final lineTotal = lineDiscounts.fold<double>(0.0, (sum, d) => sum + d);
  return wholeCartDiscount + lineTotal;
}

/// Volume 5: "each amount entered reduces a visible 'remaining'
/// figure." Not itself a validation — a negative result just means
/// payments already exceed the total, which the caller decides what to
/// do with (the same "this module computes, the UI decides" split
/// every other local calculation in this codebase follows).
double computeRemainingToPay({
  required double total,
  required List<double> paymentAmounts,
}) {
  final paid = paymentAmounts.fold<double>(0.0, (sum, amount) => sum + amount);
  return total - paid;
}

/// What ends up in the single `Sale.paymentMethod`/`SaleCreate.
/// payment_method` field when a sale had more than one payment leg —
/// the backend has no concept of a mixed-method sale (one string, not a
/// list), so something has to be chosen. `'split'` when methods
/// genuinely differ; the shared method name when they don't (recording
/// two separate cash payments is still just "cash"); `null` when there
/// were no payments at all yet, matching `Sale.paymentMethod`'s own
/// nullable, "not yet decided" meaning.
String? aggregatePaymentMethod(List<String> methods) {
  if (methods.isEmpty) return null;
  final distinct = methods.toSet();
  if (distinct.length == 1) return distinct.first;
  return 'split';
}

/// Bug fix (transaction audit center / "Paid in full" regression):
/// what `Sale.amountPaid` should actually persist — every payment leg
/// **except** a `'credit'` one. Credit extends the customer's balance
/// (`SaleRepositoryImpl._recordCreditSaleIfNeeded`, which already sums
/// the `'credit'`-method legs on its own, correctly, for exactly this
/// reason) rather than putting money in the till at sale time; it's a
/// promise, not cash collected.
///
/// Before this existed, `completeSale` summed every leg indiscriminately
/// (the same naive shape `_recordCreditSaleIfNeeded`'s own doc comment
/// already named and fixed one layer up: "Credit ₦50,000 + Mobile Money
/// ₦197,250 against a ₦247,250 total makes amountPaid == total"). That
/// made a split sale with a credit leg persist `Sale.amountPaid ==
/// Sale.total`, so `Sale.balanceDue` (`total - amountPaid`) came out
/// exactly 0 — even though the credit portion was only ever promised,
/// not collected. Every reader of that one stored field inherited the
/// same wrong picture: the transaction detail screen and printed
/// receipt both showed "Paid in full" for a sale that still had money
/// outstanding, `CashDrawerShiftRepositoryImpl.computeExpectedCash`
/// counted the uncollected credit as if it were cash in the drawer, and
/// `FinanceStatsRepositoryImpl`'s sales inflow overstated actual money
/// received by the same amount — none of them had any way to know part
/// of `amountPaid` was fictional, because the field itself was wrong at
/// the source. This is the one place that source gets fixed, so every
/// downstream reader is correct without having to know about credit at
/// all.
double computeCashAmountPaid(List<({String method, double amount})> payments) {
  return payments.where((p) => p.method != 'credit').fold<double>(0.0, (sum, p) => sum + p.amount);
}
