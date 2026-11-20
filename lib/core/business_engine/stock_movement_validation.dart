/// Local, pre-write field validation for StockMovement writes. Mirrors
/// the backend's own Pydantic constraints
/// (backend/app/schemas/inventory.py's `StockInRequest`/
/// `StockOutRequest`/`StockAdjustmentRequest`, verified directly) —
/// catching an obviously-bad value here means the cashier finds out
/// immediately, instead of writing it locally, queuing a sync task, and
/// only discovering the problem once that sync attempt comes back
/// mapped to a `BusinessRuleFailure` (core/errors/failure.dart) minutes
/// or hours later.
///
/// **Deliberately narrower than an "InventoryEngine" covering the whole
/// Inventory domain would suggest.** A first pass at this module tried
/// to port over field validation, SKU/barcode duplicate-checking, and a
/// local insufficient-stock guard together, modeled on an earlier,
/// disconnected build of this same domain. Checked each piece against
/// what this real codebase actually has a call site for:
/// - SKU/barcode duplicate checks: no local `createProduct` exists at
///   all — Product is pull-sync only (ProductRepositoryImpl.
///   syncFromServer, no local write path) — so this validation would
///   have nothing to attach to. Dropped rather than written as dead
///   code with no caller.
/// - An authoritative local insufficient-stock rule: that decision does
///   not belong in this field-validation helper. The repository currently
///   applies an optimistic guard using cached `ProductStockLevels`, while
///   the cloud command performs the authoritative check. Because the cache
///   may be stale offline, that local guard can reject a movement that the
///   server would accept; Part E tracks this as a behavior to validate and
///   decide with the product's offline-stock policy.
///
/// What's left — quantity/reason field shape — has no such staleness
/// problem: `quantity > 0` is either true or false regardless of how
/// long this device has been offline.
library;

/// Backend: `StockInRequest.quantity`/`StockOutRequest.quantity`, both
/// `Field(gt=0)`.
void validateMovementQuantity(int quantity) {
  if (quantity <= 0) {
    throw ArgumentError.value(
      quantity,
      'quantity',
      'must be > 0 (backend: StockInRequest/StockOutRequest.quantity, gt=0)',
    );
  }
}

/// Backend: `StockAdjustmentRequest.new_quantity`, `Field(ge=0)` — zero
/// is a valid target ("All sold" reaching zero is ordinary, not an edge
/// case).
void validateAdjustmentTarget(int newQuantity) {
  if (newQuantity < 0) {
    throw ArgumentError.value(
      newQuantity,
      'newQuantity',
      'must be ≥ 0 (backend: StockAdjustmentRequest.new_quantity, ge=0)',
    );
  }
}

/// Backend: `StockAdjustmentRequest.reason`, `Field(min_length=1)` —
/// required, unlike stock-in/out's optional free-text `reason`.
void validateAdjustmentReason(String? reason) {
  if (reason == null || reason.trim().isEmpty) {
    throw ArgumentError.value(
      reason,
      'reason',
      'is required for an adjustment (backend: '
          'StockAdjustmentRequest.reason, min_length=1)',
    );
  }
}
