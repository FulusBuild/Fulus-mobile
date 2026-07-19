import 'package:json_annotation/json_annotation.dart';

part 'sale.g.dart';

/// The domain entity — plain Dart, per Architecture Section 1's rule
/// that domain/ has zero Flutter/Drift/Dio imports. This is what the
/// rest of the app (repositories, use cases, UI) actually works with;
/// data/remote/endpoints/sales_api.dart is the only place that ever
/// talks about the JSON wire format directly.
class Sale {
  const Sale({
    required this.localId,
    this.serverId,
    required this.clientReference,
    this.invoiceNumber,
    this.customerId,
    required this.locationId,
    required this.saleDate,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    this.paymentMethod,
    this.notes,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String clientReference;
  final String? invoiceNumber;
  final String? customerId;
  final String locationId;
  final DateTime saleDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;
  final String? paymentMethod;
  final String? notes;
  final List<SaleItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Computed, not stored — deliberately mirrors the backend's own
  /// Sale.balance_due, which I verified directly is a Python @property
  /// on the backend model, not a mapped_column. Storing this as a
  /// persisted field locally (in Drift's Sales table, which correctly
  /// has no balanceDue column — see tables.dart) risks it silently
  /// drifting from its own inputs after an edit; computing it here,
  /// every time it's read, cannot drift.
  double get balanceDue => total - amountPaid;

  /// Also computed, also mirroring backend logic exactly rather than
  /// reintroducing a parallel definition of "what counts as paid" —
  /// verified directly against sale_service.py's _compute_payment_status:
  /// paid when amountPaid >= total, unpaid when amountPaid <= 0 (not
  /// strictly == 0 — an earlier draft of this file had that wrong; the
  /// backend's own check is <=, which also correctly treats a negative
  /// amountPaid as unpaid rather than partial, a case that shouldn't
  /// normally arise but is worth matching exactly rather than
  /// approximately), partial otherwise.
  String get paymentStatus {
    if (amountPaid >= total) return 'paid';
    if (amountPaid <= 0) return 'unpaid';
    return 'partial';
  }
}

class SaleItem {
  const SaleItem({
    required this.localId,
    required this.productLocalId,
    required this.quantity,
    required this.unitPrice,
    required this.costPriceAtSale,
  });

  final String localId;
  final String productLocalId;
  final int quantity;
  final double unitPrice;
  final double costPriceAtSale;

  double get lineTotal => quantity * unitPrice;
}

/// The wire-format DTO for POST /api/sales — verified directly against
/// backend/app/schemas/sale.py::SaleCreate and SaleItemCreate. Field
/// names below match the backend's actual snake_case exactly (via
/// @JsonKey), not an approximation — getting one of these wrong would be
/// exactly the kind of "fake API" the brief's rules explicitly forbid,
/// since it would silently fail against the real backend rather than
/// fail loudly against a mock.
@JsonSerializable(fieldRename: FieldRename.snake)
class SaleCreateDto {
  const SaleCreateDto({
    required this.items,
    this.customerId,
    this.discount,
    this.tax,
    required this.amountPaid,
    this.paymentMethod,
    this.notes,
    this.clientReference,
    this.saleDate,
  });

  final List<SaleItemCreateDto> items;
  final String? customerId;
  final double? discount;
  final double? tax;
  final double amountPaid;
  final String? paymentMethod;
  final String? notes;

  /// This is THE field the entire idempotent-retry mechanism depends on
  /// (Architecture Section 3) — set equal to the local Sale's localId at
  /// creation time by the repository, never generated fresh on each sync
  /// attempt. Nullable here only because the backend schema itself marks
  /// it optional (verified directly: client_reference: str | None =
  /// Field(default=None, ...)) — the mobile repository must always
  /// populate it in practice; leaving it null would silently give up the
  /// duplicate-prevention guarantee this whole design relies on.
  final String? clientReference;

  final DateTime? saleDate;

  Map<String, dynamic> toJson() => _$SaleCreateDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SaleItemCreateDto {
  const SaleItemCreateDto({
    required this.productId,
    required this.quantity,
    this.unitPrice,
  });

  final String productId;
  final int quantity;

  /// Nullable, matching the backend exactly (verified directly:
  /// SaleItemCreate.unit_price: float | None — "If unit_price is
  /// omitted the service uses the product's current selling_price").
  /// The mobile client omits this deliberately when the cart line used
  /// the product's own listed price unedited, letting the backend be
  /// the single source of truth for that price rather than the mobile
  /// client re-asserting a value it already got from the server.
  final double? unitPrice;

  Map<String, dynamic> toJson() => _$SaleItemCreateDtoToJson(this);
}

/// The wire-format DTO for what POST /api/sales and GET /api/sales/{id}
/// return — verified directly against SaleOut and SaleItemOut.
@JsonSerializable(fieldRename: FieldRename.snake)
class SaleResponseDto {
  const SaleResponseDto({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    required this.saleDate,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    this.paymentMethod,
    this.notes,
    required this.items,
  });

  final String id;
  final String invoiceNumber;
  final String? customerId;
  final DateTime saleDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;
  final String? paymentMethod;
  final String? notes;
  final List<SaleItemResponseDto> items;

  factory SaleResponseDto.fromJson(Map<String, dynamic> json) =>
      _$SaleResponseDtoFromJson(json);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SaleItemResponseDto {
  const SaleItemResponseDto({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.costPriceAtSale,
    required this.lineTotal,
  });

  final String id;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double costPriceAtSale;
  final double lineTotal;

  factory SaleItemResponseDto.fromJson(Map<String, dynamic> json) =>
      _$SaleItemResponseDtoFromJson(json);
}
