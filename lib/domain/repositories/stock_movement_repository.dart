import '../entities/stock_movement.dart';

/// Architecture Section 4's repository pattern, applied to stock
/// movements. Write-capable from mobile — recording a manual adjustment
/// (recount, damage/waste) is a normal on-device action — but see
/// [recordMovement]'s own note on which movement types that actually
/// covers.
abstract class StockMovementRepository {
  /// Only ever called with [StockMovementType.stockIn],
  /// [.stockOut], or [.adjustment] — never [.sale], which the backend
  /// creates automatically as a side effect of a sale itself (verified
  /// directly: see StockMovementType's own doc comment), not something
  /// a mobile stock-adjustment form would ever submit. Not enforced by
  /// this method's own signature (StockMovementDraft accepts any
  /// StockMovementType) since the actual gate belongs in whatever UI
  /// builds the draft — the one place that already knows it's building
  /// a manual adjustment form, not a checkout flow.
  Future<StockMovement> recordMovement(StockMovementDraft draft);

  Stream<List<StockMovement>> watchMovementsForLocation(String locationId);

  Future<void> markSynced({required String localId, required String serverId});
}
