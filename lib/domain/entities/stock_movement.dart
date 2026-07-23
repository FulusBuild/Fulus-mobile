/// Mirrors backend/app/models/inventory.py's StockMovement.movement_type
/// values exactly: in / out / adjustment / sale — verified directly, not
/// assumed. This deliberately does NOT include "transfer": tables.dart's
/// own comment on the StockMovements table (and its toLocationId column)
/// describes a transfer movement type, but grepping the entire backend
/// inventory model/schema/service/router turns up zero mentions of
/// transfer anywhere — it does not exist server-side today, despite
/// Architecture Section 7a naming "the Transfer feature" as something
/// ProductStockLevels supports. This is a real discrepancy between the
/// mobile schema (built in an earlier session) and the actual backend,
/// surfaced here rather than silently modeled around, the same way
/// SaleSyncHandler names the product/customer serverId gap.
enum StockMovementType {
  stockIn,
  stockOut,
  adjustment,

  /// An automatic byproduct of a sale being created server-side — never
  /// something a mobile write should submit itself (see
  /// StockMovementRepository.recordMovement's own doc comment).
  sale;

  String get wireValue => switch (this) {
        StockMovementType.stockIn => 'in',
        StockMovementType.stockOut => 'out',
        StockMovementType.adjustment => 'adjustment',
        StockMovementType.sale => 'sale',
      };

  static StockMovementType fromWireValue(String value) => switch (value) {
        'in' => StockMovementType.stockIn,
        'out' => StockMovementType.stockOut,
        'adjustment' => StockMovementType.adjustment,
        'sale' => StockMovementType.sale,
        _ => throw ArgumentError('Unknown movement type: $value'),
      };
}

class StockMovement {
  const StockMovement({
    required this.localId,
    this.serverId,
    required this.productLocalId,
    required this.locationId,
    this.toLocationId,
    required this.movementType,
    required this.quantity,
    this.reason,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String productLocalId;
  final String locationId;

  /// Present in the schema (tables.dart) but not currently meaningful —
  /// see [StockMovementType]'s own doc comment on why "transfer" (the
  /// only movement type that would ever populate this) doesn't exist
  /// backend-side yet. Kept here because the column exists; not
  /// expected to be set by any current write path.
  final String? toLocationId;

  final StockMovementType movementType;
  final int quantity;
  final String? reason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// The not-yet-persisted input to StockMovementRepository.recordMovement.
class StockMovementDraft {
  const StockMovementDraft({
    required this.productLocalId,
    required this.locationId,
    required this.movementType,
    required this.quantity,
    this.reason,
  });

  final String productLocalId;
  final String locationId;
  final StockMovementType movementType;
  final int quantity;
  final String? reason;

  StockMovement toStockMovementEntity({required String localId}) {
    final now = DateTime.now();
    return StockMovement(
      localId: localId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: movementType,
      quantity: quantity,
      reason: reason,
      createdAt: now,
      updatedAt: now,
    );
  }
}
