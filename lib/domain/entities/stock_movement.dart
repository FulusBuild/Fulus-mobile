import 'package:json_annotation/json_annotation.dart';

part 'stock_movement.g.dart';

/// Mirrors backend/app/models/inventory.py's StockMovement.movement_type
/// values as they exist TODAY: in / out / adjustment / sale — verified
/// directly against two separate backend snapshots during this
/// redesign. [transfer] is the one value with no backend endpoint yet,
/// and deliberately included anyway — see its own doc comment for why
/// this isn't the same situation as a wrong assumption.
enum StockMovementType {
  stockIn,
  stockOut,
  adjustment,

  /// An automatic byproduct of a sale being created server-side — never
  /// something a mobile write should submit itself (see
  /// StockMovementRepository.recordStockIn/.recordStockOut/
  /// .recordAdjustment's own doc comments, and
  /// StockMovementSyncHandler.sync's explicit rejection of this case).
  sale,

  /// CORRECTED — an earlier pass through this file removed this value
  /// entirely, reasoning that since no backend endpoint for it exists
  /// today (still true — grepped twice, against two separate backend
  /// snapshots, zero mentions anywhere in models/schemas/services/
  /// routers), the whole concept must have been invented in error. That
  /// conclusion was wrong, reached without ever actually reading the two
  /// primary source documents this codebase's comments constantly
  /// reference. They're unambiguous: the Product Design Bible's Volume
  /// 6, Decision 21 designs Transfer as a real, deliberate product
  /// feature (moves stock from one location's count to another's,
  /// shown only once a second location exists), and Architecture
  /// Section 7a's own table states "Transfer specifically needs two
  /// location references (from/to) on the one movement record" as a
  /// schema requirement, sequenced into Phase 2 by the roadmap (Section
  /// 14) — deliberately not built server-side yet, in exactly the same
  /// "schema ready ahead of the feature" way Sale/Expense/Income's
  /// locationId columns exist from Phase 0 despite their own user-facing
  /// features landing later too. "No backend endpoint exists today" and
  /// "this doesn't exist" are different claims; only the first one was
  /// ever actually verified. No write method on StockMovementRepository
  /// constructs this value yet (there is still, genuinely, no endpoint
  /// to call) — this is schema/type groundwork for Phase 2, not a
  /// claim that Transfer is buildable today.
  transfer;

  String get wireValue => switch (this) {
        StockMovementType.stockIn => 'in',
        StockMovementType.stockOut => 'out',
        StockMovementType.adjustment => 'adjustment',
        StockMovementType.sale => 'sale',
        StockMovementType.transfer => 'transfer',
      };

  static StockMovementType fromWireValue(String value) => switch (value) {
        'in' => StockMovementType.stockIn,
        'out' => StockMovementType.stockOut,
        'adjustment' => StockMovementType.adjustment,
        'sale' => StockMovementType.sale,
        'transfer' => StockMovementType.transfer,
        _ => throw ArgumentError('Unknown movement type: $value'),
      };
}

/// A single ledger entry. Deliberately NOT one generic "create a stock
/// movement" shape with a uniform quantity field — that was this file's
/// own earlier, wrong assumption, built before the real backend API was
/// checked. Verified directly against app/schemas/inventory.py and
/// app/routers/inventory.py: there is no single create endpoint. Three
/// separate ones exist --
///   POST /products/{id}/stock-in    (StockInRequest: quantity, reason?)
///   POST /products/{id}/stock-out   (StockOutRequest: quantity, reason?)
///   POST /products/{id}/adjust-stock (StockAdjustmentRequest: new_quantity,
///                                     reason — required, not optional)
/// -- and adjust-stock's new_quantity is an ABSOLUTE target, not a delta
/// like the other two; the backend computes its own delta server-side
/// (inventory_service.adjust_stock). [quantity] and [newQuantity] below
/// exist for exactly that split — see tables.dart's own comment on the
/// StockMovements table for the full reasoning on why they're separate,
/// both-nullable fields rather than one column.
class StockMovement {
  const StockMovement({
    required this.localId,
    this.serverId,
    required this.productLocalId,
    required this.locationId,
    this.toLocationId,
    required this.movementType,
    this.quantity,
    this.newQuantity,
    this.reason,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String productLocalId;
  final String locationId;

  /// Set only for [StockMovementType.transfer] — see that value's own
  /// doc comment on why this field exists in the schema despite no
  /// write path constructing one yet (Phase 2, not built server-side).
  final String? toLocationId;

  final StockMovementType movementType;

  /// The delta. Set for [StockMovementType.stockIn]/[.stockOut] (always
  /// positive, matching StockInRequest/StockOutRequest.quantity's own
  /// `gt=0` constraint — direction comes from movementType, not sign).
  /// Always null for [.adjustment] — see [newQuantity]'s own doc comment
  /// on why this device cannot know that row's true delta.
  final int? quantity;

  /// The absolute target. Set only for [StockMovementType.adjustment],
  /// matching StockAdjustmentRequest.new_quantity exactly. Always null
  /// otherwise. This device deliberately does NOT compute and store a
  /// delta for an adjustment row, even after a successful sync: the
  /// backend computes `new_quantity - product.current_stock` against
  /// its OWN authoritative current_stock at the moment it processes the
  /// request (inventory_service.adjust_stock), which this device cannot
  /// reliably reproduce locally, especially after being offline for a
  /// while during which other movements it doesn't know about may have
  /// happened. The true delta lives server-side, in that request's own
  /// resulting StockMovement row (visible via GET .../history) — this
  /// local row's job is to be an honest record of what was submitted,
  /// not a mirror of a number this device was never in a position to
  /// compute correctly.
  final int? newQuantity;

  final String? reason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Mirrors StockInRequest exactly. Only ever valid to call when
  /// [movementType] is [StockMovementType.stockIn] — StockMovementSyncHandler
  /// is the only caller, and it always checks movementType first.
  StockInCreateDto toStockInDto({required String clientReference}) {
    assert(movementType == StockMovementType.stockIn);
    return StockInCreateDto(
      quantity: quantity!,
      reason: reason,
      locationId: locationId,
      clientReference: clientReference,
    );
  }

  /// Mirrors StockOutRequest exactly. Same calling convention as
  /// [toStockInDto].
  StockOutCreateDto toStockOutDto({required String clientReference}) {
    assert(movementType == StockMovementType.stockOut);
    return StockOutCreateDto(
      quantity: quantity!,
      reason: reason,
      locationId: locationId,
      clientReference: clientReference,
    );
  }

  /// Mirrors StockAdjustmentRequest exactly, including reason being
  /// REQUIRED there (unlike stock-in/out) — StockAdjustmentDraft already
  /// enforces this at construction time, so the `!` here reflects that
  /// guarantee, not an unchecked assumption. Same calling convention as
  /// [toStockInDto].
  StockAdjustmentCreateDto toStockAdjustmentDto({required String clientReference}) {
    assert(movementType == StockMovementType.adjustment);
    return StockAdjustmentCreateDto(
      newQuantity: newQuantity!,
      reason: reason!,
      locationId: locationId,
      clientReference: clientReference,
    );
  }
}

/// POST /products/{id}/stock-in's body — mirrors StockInRequest exactly.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class StockInCreateDto {
  const StockInCreateDto({
    required this.quantity,
    this.reason,
    required this.locationId,
    this.clientReference,
  });

  final int quantity;
  final String? reason;
  // Architecture Section 7a / migration 0020_stock_movement_location:
  // required on the backend now (StockInRequest.location_id). Was
  // silently dropped here before that migration existed — locationId
  // has been on the StockMovement domain entity and every Draft below
  // since this file was first built, it just had nowhere real to go on
  // the wire until the backend actually gained the column.
  final String locationId;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$StockInCreateDtoToJson(this);
}

/// POST /products/{id}/stock-out's body — mirrors StockOutRequest
/// exactly.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class StockOutCreateDto {
  const StockOutCreateDto({
    required this.quantity,
    this.reason,
    required this.locationId,
    this.clientReference,
  });

  final int quantity;
  final String? reason;
  final String locationId;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$StockOutCreateDtoToJson(this);
}

/// POST /products/{id}/adjust-stock's body — mirrors
/// StockAdjustmentRequest exactly, including reason being required
/// (`str = Field(min_length=1, ...)`, no default), not optional like the
/// other two requests.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class StockAdjustmentCreateDto {
  const StockAdjustmentCreateDto({
    required this.newQuantity,
    required this.reason,
    required this.locationId,
    this.clientReference,
  });

  final int newQuantity;
  final String reason;
  final String locationId;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$StockAdjustmentCreateDtoToJson(this);
}

/// The not-yet-persisted input to StockMovementRepository.recordStockIn.
/// A distinct draft type per write kind (this, StockOutDraft,
/// StockAdjustmentDraft below) rather than one generic
/// StockMovementDraft with a movementType selector — the old, single-
/// shape design this replaces — because the three real backend requests
/// genuinely have different required fields (StockAdjustmentDraft.reason
/// is required, these two are not) that a single shared draft could only
/// represent by making everything optional and hoping the caller passes
/// the right combination.
class StockInDraft {
  const StockInDraft({
    required this.productLocalId,
    required this.locationId,
    required this.quantity,
    this.reason,
  });

  final String productLocalId;
  final String locationId;
  final int quantity;
  final String? reason;

  StockMovement toStockMovementEntity({required String localId}) {
    final now = DateTime.now();
    return StockMovement(
      localId: localId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: StockMovementType.stockIn,
      quantity: quantity,
      reason: reason,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// The not-yet-persisted input to StockMovementRepository.recordStockOut.
class StockOutDraft {
  const StockOutDraft({
    required this.productLocalId,
    required this.locationId,
    required this.quantity,
    this.reason,
  });

  final String productLocalId;
  final String locationId;
  final int quantity;
  final String? reason;

  StockMovement toStockMovementEntity({required String localId}) {
    final now = DateTime.now();
    return StockMovement(
      localId: localId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: StockMovementType.stockOut,
      quantity: quantity,
      reason: reason,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// The not-yet-persisted input to
/// StockMovementRepository.recordAdjustment. [reason] is required here,
/// not optional — matching StockAdjustmentRequest.reason's own
/// `min_length=1` constraint (no default) exactly, unlike
/// StockInDraft/StockOutDraft's optional reason.
class StockAdjustmentDraft {
  const StockAdjustmentDraft({
    required this.productLocalId,
    required this.locationId,
    required this.newQuantity,
    required this.reason,
  });

  final String productLocalId;
  final String locationId;
  final int newQuantity;
  final String reason;

  StockMovement toStockMovementEntity({required String localId}) {
    final now = DateTime.now();
    return StockMovement(
      localId: localId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: StockMovementType.adjustment,
      newQuantity: newQuantity,
      reason: reason,
      createdAt: now,
      updatedAt: now,
    );
  }
}
