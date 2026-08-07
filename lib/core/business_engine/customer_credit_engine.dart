/// Pure, local business logic for the Customers domain — Bible-sourced
/// rules with no backend equivalent to check against (confirmed by
/// grepping backend/app/models/customer.py and
/// backend/app/services/customer_service.py directly: no credit_limit,
/// no purchase_count, no repayment-recording function of any kind
/// exist server-side). See `stock_movement_validation.dart`'s own doc
/// comment for the same "check what actually has a call site before
/// porting a broader engine over" discipline applied here.
///
/// **What this deliberately does NOT include, and why:**
/// - Field-length validation (name/phone/email/notes) — already
///   enforced both by `CustomerCreateDto`'s own Dart types matching the
///   backend's Field() constraints and by the 422 the backend itself
///   returns if something slips through; a local mirror of that would
///   duplicate, not add, coverage. Different from StockMovement's
///   quantity/reason checks, which genuinely have no earlier gate.
/// - Duplicate phone/email detection — the backend already does this
///   and returns `duplicate_warning` on the create response (see
///   CustomerResponseDto's own doc comment for the full trail); a local
///   pre-check would need to search this device's local Customers table,
///   which could easily be missing customers created on OTHER devices
///   that haven't synced down to this one yet — a false "looks unique"
///   answer would be actively worse than deferring to the check that's
///   already correct.
library;

/// Volume 7: "An owner extending credit past a customer's set limit
/// sees a plain warning... but can proceed." Returns the overage
/// (always positive) if the proposed new balance would exceed
/// [creditLimit], or `null` if there's nothing to warn about —
/// including when [creditLimit] itself is `null` (no limit set means no
/// warning ever applies). **Never throws** — informational, not a
/// block; Decision 23 is explicit that a limit is "a guide," not an
/// enforced ceiling.
double? checkCreditLimitWarning({
  required double currentBalance,
  required double proposedAdditionalCredit,
  required double? creditLimit,
}) {
  if (creditLimit == null) return null;
  final projectedBalance = currentBalance + proposedAdditionalCredit;
  if (projectedBalance <= creditLimit) return null;
  return projectedBalance - creditLimit;
}

/// Volume 7 Loyalty: "an optional owner-set threshold (e.g., every 10th
/// purchase)." Read literally as a modulo check — retriggers at every
/// multiple (10, 20, 30, ...), not a counter that resets after being
/// rewarded once; no reset mechanism is described in the Bible.
bool hasReachedLoyaltyThreshold({
  required int purchaseCount,
  required int? loyaltyThreshold,
}) {
  if (loyaltyThreshold == null || loyaltyThreshold <= 0) return false;
  if (purchaseCount <= 0) return false;
  return purchaseCount % loyaltyThreshold == 0;
}

/// The repayment-capping rule behind Volume 7's named failure scenario:
/// "Repayment recorded larger than the balance owed: the balance simply
/// goes to zero; the excess is flagged plainly rather than silently
/// disappearing, for the owner to resolve." Returns `(newBalance,
/// excessAmount)` — `excessAmount` is `0` in the ordinary case where the
/// repayment didn't exceed what was owed.
({double newBalance, double excessAmount}) computeRepaymentEffect({
  required double currentBalance,
  required double repaymentAmount,
}) {
  if (repaymentAmount <= currentBalance) {
    return (newBalance: currentBalance - repaymentAmount, excessAmount: 0.0);
  }
  return (newBalance: 0.0, excessAmount: repaymentAmount - currentBalance);
}
