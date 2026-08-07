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
