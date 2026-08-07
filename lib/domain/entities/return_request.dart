import 'package:json_annotation/json_annotation.dart';

part 'return_request.g.dart';

/// Mirrors the backend's `Return` status values exactly:
/// pending → approved/rejected → (approved only) completed. See
/// tables.dart's `ReturnRequests` doc comment for the full context.
enum ReturnStatus {
  /// Volume 5: "Like discounts, an employee-initiated refund requires
  /// the same owner approval as Decision 16." Whether a given return
  /// lands here or skips straight to `approved` is decided by the
  /// *caller* of `createReturn` (`autoApprove`), not this module — same
  /// "mechanics here, permission decision elsewhere" split every
  /// Auth-coupled decision in this codebase follows.
  pending,
  approved,
  rejected,

  /// Only reachable from `approved` — mirrors `complete_return`'s own
  /// guard: "This return must be approved before it can be completed."
  completed;
}

/// Named `ReturnRequest` rather than `Return` — see tables.dart's own
/// doc comment for why (`Return` collides with Dart's control-flow
/// vocabulary badly enough to read poorly everywhere it'd appear).
class ReturnRequest {
  const ReturnRequest({
    required this.localId,
    this.serverId,
    required this.originalSaleLocalId,
    required this.status,
    required this.returnReason,
    required this.refundAmount,
    required this.refundMethod,
    required this.inventoryRestored,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String localId;
  final String? serverId;
  final String originalSaleLocalId;
  final ReturnStatus status;

  /// Backend: `Return.return_reason`, `Field(min_length=1, max_length=500)`
  /// — required, unlike a stock-out's optional free-text note.
  final String returnReason;

  /// Computed by `ReturnRepository.createReturn` from each returned
  /// line's *weighted-average* price within the original sale — see
  /// that method's own doc comment for why a plain per-line price isn't
  /// enough. Never caller-supplied.
  final double refundAmount;

  /// Same plain-string choice `SalePayment.method` made — defaults to
  /// the original sale's payment method in the UI (Volume 5: "matches
  /// the original payment method by default, with a manual override
  /// always available"), but that default-selection is a UI concern;
  /// this just stores whatever was ultimately chosen.
  final String refundMethod;

  final bool inventoryRestored;
  final List<ReturnItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  ReturnRequest copyWith({
    ReturnStatus? status,
    bool? inventoryRestored,
    DateTime? updatedAt,
    DateTime? Function()? completedAt,
  }) {
    return ReturnRequest(
      localId: localId,
      serverId: serverId,
      originalSaleLocalId: originalSaleLocalId,
      status: status ?? this.status,
      returnReason: returnReason,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      inventoryRestored: inventoryRestored ?? this.inventoryRestored,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
    );
  }
}

/// One returned product+quantity. Backend stores `items` as a JSON blob
/// directly on the `Return` row — see tables.dart's own doc comment for
/// why this schema uses a real child table instead.
class ReturnItem {
  const ReturnItem({
    required this.localId,
    required this.returnLocalId,
    required this.productLocalId,
    required this.quantity,
  });

  final String localId;
  final String returnLocalId;
  final String productLocalId;
  final int quantity;
}

/// Input shape for `ReturnRepository.createReturn` — one requested
/// product+quantity, before it's been checked against what's actually
/// still eligible.
class ReturnItemRequest {
  const ReturnItemRequest({required this.productLocalId, required this.quantity});

  final String productLocalId;
  final int quantity;
}

/// Return shape for `ReturnRepository.getReturnEligibility` — mirrors
/// `pos_service.get_return_eligibility`'s response shape: "so the UI can
/// show/limit the right amount *before* the cashier tries to submit a
/// return."
class ReturnEligibilityLine {
  const ReturnEligibilityLine({
    required this.productLocalId,
    required this.purchasedQuantity,
    required this.alreadyReturned,
    required this.remainingReturnable,
  });

  final String productLocalId;
  final int purchasedQuantity;
  final int alreadyReturned;
  final int remainingReturnable;
}

// ---- Wire DTOs — verified directly against backend/app/schemas/pos.py ----

@JsonSerializable(fieldRename: FieldRename.snake)
class ReturnItemDto {
  const ReturnItemDto({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() => _$ReturnItemDtoToJson(this);

  factory ReturnItemDto.fromJson(Map<String, dynamic> json) =>
      _$ReturnItemDtoFromJson(json);
}

/// **No `client_reference`** — checked directly against `ReturnCreate`,
/// which has no such field. See tables.dart's `ReturnRequests` doc
/// comment for the confirmed gap this reflects.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ReturnCreateDto {
  const ReturnCreateDto({
    required this.originalSaleId,
    required this.items,
    required this.returnReason,
    required this.refundMethod,
  });

  final String originalSaleId;
  final List<ReturnItemDto> items;
  final String returnReason;
  final String refundMethod;

  Map<String, dynamic> toJson() => _$ReturnCreateDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ReturnResponseDto {
  const ReturnResponseDto({
    required this.id,
    required this.originalSaleId,
    required this.status,
    required this.returnReason,
    required this.refundAmount,
    required this.refundMethod,
    required this.items,
    required this.inventoryRestored,
  });

  final String id;
  final String originalSaleId;
  final String status;
  final String returnReason;
  final double refundAmount;
  final String refundMethod;
  final List<ReturnItemDto> items;
  final bool inventoryRestored;

  factory ReturnResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ReturnResponseDtoFromJson(json);
}

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ReturnApproveDto {
  const ReturnApproveDto({required this.approve});

  final bool approve;

  Map<String, dynamic> toJson() => _$ReturnApproveDtoToJson(this);
}
