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
    this.cashierUserId,
    required this.saleDate,
    required this.subtotal,
    this.wholeCartDiscount = 0.0,
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

  /// **New in schema v4.** Nullable — see `Sales.cashierUserId`'s own
  /// doc comment in tables.dart for why. Populated by
  /// SaleRepositoryImpl.createSale from whichever local Users account
  /// is signed in at the moment of sale creation; never overwritten
  /// after that.
  final String? cashierUserId;
  final DateTime saleDate;
  final double subtotal;

  /// The whole-cart-discount component specifically, kept alongside
  /// `discount` (the combined total that actually syncs) — see
  /// tables.dart's `Sales.wholeCartDiscount` doc comment for why the
  /// breakdown is worth keeping even once a sale is finished, not just
  /// during cart-editing.
  final double wholeCartDiscount;
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
    this.productLocalId,
    this.description = '',
    required this.quantity,
    required this.unitPrice,
    required this.costPriceAtSale,
    this.lineDiscount = 0.0,
  });

  final String localId;

  /// `null` for a Quick Sale line (Volume 5: "for anything not in the
  /// catalog at all"). Real, structural divergence from the backend —
  /// see tables.dart's `SaleItems.productLocalId` doc comment for the
  /// confirmed backend gap this reflects (`SaleItemCreate.product_id`
  /// is required, no default).
  final String? productLocalId;

  /// New — no backend equivalent (`SaleItemOut` has no name field at
  /// all). The only way a Quick Sale line can have a name; also keeps a
  /// receipt's wording stable if a real product gets renamed later.
  final String description;

  final int quantity;
  final double unitPrice;
  final double costPriceAtSale;

  /// New — Volume 5's per-line discount. No backend column; folds into
  /// `Sale.discount` alongside the whole-cart discount — see that
  /// field's own doc comment. NOT netted into [lineTotal] below —
  /// `SaleDraft.subtotal` sums every item's `lineTotal` directly to
  /// produce `Sale.subtotal`, which the backend defines as the raw,
  /// pre-discount total (`sale_service.create_sale`: `subtotal =
  /// round(sum(qty * unit_price), 2)`, discount subtracted separately
  /// afterward) — netting it in here would have silently corrupted that
  /// existing, correct aggregation.
  final double lineDiscount;

  /// Raw, pre-discount — `quantity * unitPrice`, matching
  /// `SaleItemOut.line_total` exactly. A line's actual net contribution
  /// after its own discount is `lineTotal - lineDiscount`, computed
  /// where needed (a receipt, a per-line display) rather than baked in
  /// here, so this keeps meaning the one thing `SaleDraft.subtotal`
  /// needs it to mean.
  double get lineTotal => quantity * unitPrice;
}

/// The wire-format DTO for POST /api/sales — verified directly against
/// backend/app/schemas/sale.py::SaleCreate and SaleItemCreate. Field
/// names below match the backend's actual snake_case exactly (via
/// @JsonKey), not an approximation — getting one of these wrong would be
/// exactly the kind of "fake API" the brief's rules explicitly forbid,
/// since it would silently fail against the real backend rather than
/// fail loudly against a mock.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class SaleCreateDto {
  const SaleCreateDto({
    required this.items,
    this.customerId,
    required this.locationId,
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
  // Architecture Section 7a / migration 0017_sale_location: required on
  // the backend now (SaleCreate.location_id). This was the real,
  // critical gap this whole file's own doc comments got wrong: they
  // claimed (accurately, at the time they were written) that
  // SaleCreateDto deliberately never sends locationId because
  // SaleCreate had no such field server-side. That stopped being true
  // the moment the backend migration landed, and nothing here was
  // updated to match — every sale sync from mobile would have gotten a
  // 422 from the backend the moment that migration shipped, including
  // through the most mature vertical in the app.
  final String locationId;
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

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
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
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
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

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
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
