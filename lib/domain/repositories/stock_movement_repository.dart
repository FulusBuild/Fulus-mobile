import '../entities/stock_movement.dart';

/// Architecture Section 4's repository pattern, applied to stock
/// movements. Write-capable from mobile — recording a manual adjustment
/// (recount, damage/waste) is a normal on-device action. Three write
/// methods, not one generic `recordMovement(StockMovementDraft)` — the
/// old shape this replaces — because the real backend has three
/// genuinely different request shapes (see stock_movement.dart's own
/// doc comment on StockMovement for the full verification), not one
/// generic endpoint with a movementType selector. Deliberately only
/// three, covering [StockMovementType.stockIn]/[.stockOut]/
/// [.adjustment] — the other two enum values are unreachable through
/// any method here, for two different reasons: [.sale] because it's
/// created automatically server-side as a byproduct of a sale, never
/// something a mobile form submits; [.transfer] because it's a real,
/// intended Phase 2 feature (Product Design Bible Volume 6, Decision
/// 21; Architecture Section 7a) with no backend endpoint built yet —
/// see StockMovementType.transfer's own doc comment before assuming
/// that's the same kind of "doesn't exist" as .sale.
abstract class StockMovementRepository {
  Future<StockMovement> recordStockIn(StockInDraft draft);

  Future<StockMovement> recordStockOut(StockOutDraft draft);

  Future<StockMovement> recordAdjustment(StockAdjustmentDraft draft);

  Stream<List<StockMovement>> watchMovementsForLocation(String locationId);

  /// Needed by StockMovementSyncHandler to fetch the persisted movement
  /// at sync time (matching CustomerRepository.getCustomerById/
  /// ExpenseRepository.getExpenseById/IncomeRecordRepository.getIncomeRecordById
  /// exactly).
  Future<StockMovement?> getStockMovementById(String localId);

  /// Deliberately NOT `markSynced({localId, serverId})` like every other
  /// repository in this codebase — a real, verified difference, not an
  /// inconsistency: none of the three write endpoints (stock-in,
  /// stock-out, adjust-stock) ever return a server id FOR THE MOVEMENT
  /// itself. All three return ProductOut (the product, updated) —
  /// verified directly against routers/inventory.py's
  /// response_model=ProductOut on all three routes. A real StockMovement
  /// id does exist server-side (StockMovementOut.id, visible via GET
  /// .../history), but no write response this device ever receives
  /// contains it. Forcing a `required String serverId` parameter here
  /// would mean either passing a fabricated placeholder (dishonest — the
  /// exact kind of fake-safety this codebase's own discipline elsewhere
  /// is about catching) or awkwardly making every other entity's
  /// markSynced signature nullable to accommodate this one case that
  /// doesn't have one. A distinctly-named, distinctly-shaped method for
  /// a distinctly-shaped reality instead.
  Future<void> markSettled({required String localId});
}
