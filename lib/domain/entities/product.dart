import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

/// Mirrors the Products table exactly — catalog fields only.
/// currentStock deliberately does NOT live here (see [ProductWithStock]
/// below) — Architecture Section 7a: stock is per-location, catalog
/// fields are business-wide, and duplicating catalog fields per
/// location would be the wrong way to model that split.
class Product {
  const Product({
    required this.localId,
    this.serverId,
    required this.name,
    required this.sku,
    this.barcode,
    this.categoryId,
    this.supplierId,
    required this.costPrice,
    required this.sellingPrice,
    required this.lowStockThreshold,
    required this.isActive,
    this.tracksStock = true,
    this.unit = 'piece',
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final double costPrice;
  final double sellingPrice;
  final int lowStockThreshold;
  final bool isActive;

  /// **Bible-only** (Product Design Bible Volume 6, Decision 18:
  /// "Stock tracking is opt-out per product, not mandatory"). No backend
  /// column — confirmed directly against backend/app/models/inventory.py
  /// — so there is nothing in ProductResponseDto to read this from; a
  /// synced-down product always gets the column default (`true`) on
  /// first insert. Set locally via ProductRepository.setLocalOverrides,
  /// which — deliberately — is the only write path that ever touches
  /// this column, so a routine re-sync (syncFromServer's
  /// insertOnConflictUpdate) never has a value to overwrite it with and
  /// leaves whatever was set here untouched. Consumed by
  /// watchLowStockProducts/watchProducts' own low-stock predicate and by
  /// InventoryEngine.isLowStock/stockValue.
  final bool tracksStock;

  /// **Bible-only** (Volume 6: "Unit... Defaults to 'piece'").
  /// Display-only. Same "no backend column, set via setLocalOverrides,
  /// survives re-sync" status as [tracksStock].
  final String unit;

  /// **Bible-only** (Volume 6: "Photo — Strongly encouraged"). A local
  /// file path — no photo-upload endpoint exists for products in the
  /// backend today, so there is nowhere to sync this field to yet. Same
  /// survives-re-sync status as [tracksStock]/[unit].
  final String? photoPath;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Fields needed to create a [Product] — Product Design Bible Volume 6,
/// "Adding & Managing Products": "Add Product opens with just Name and
/// Price visible... everything else... optional." [locationId] isn't a
/// Bible field on the product itself (catalog fields are business-wide,
/// same reasoning as [Product] itself not carrying stock) — it's here
/// only so ProductRepositoryImpl can seed an initial
/// ProductStockLevels row at the same location every other read on this
/// repository is already scoped to, closing the gap
/// SaleRepositoryImpl._decrementLocalStock's own comment names ("seeding
/// initial stock levels is real, undone work" — it's done here, at
/// creation time, which is where it actually belongs, not invented
/// retroactively inside a sale).
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.sku,
    required this.costPrice,
    required this.sellingPrice,
    required this.locationId,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.lowStockThreshold = 10,
    this.initialStock = 0,
  });

  final String name;
  final String sku;
  final double costPrice;
  final double sellingPrice;
  final String locationId;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final int lowStockThreshold;
  final int initialStock;

  Product toProductEntity({required String localId}) {
    final now = DateTime.now();
    return Product(
      localId: localId,
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Mirrors backend/app/schemas/inventory.py's ProductCreate exactly,
/// verified directly — POST /api/inventory/products's request body.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ProductCreateDto {
  const ProductCreateDto({
    required this.name,
    required this.sku,
    required this.costPrice,
    required this.sellingPrice,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.lowStockThreshold = 10,
    this.initialStock = 0,
  });

  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final double costPrice;
  final double sellingPrice;
  final int lowStockThreshold;
  final int initialStock;

  Map<String, dynamic> toJson() => _$ProductCreateDtoToJson(this);
}

/// Mirrors ProductUpdate exactly, verified directly — every field
/// optional (a genuine partial update; PATCH .../products/{id}), unlike
/// ProductCreateDto above. `null` here (via json_serializable's default
/// `includeIfNull: true` behavior) means "don't change this field," NOT
/// "clear it" — matches how the backend's own ProductUpdate is read
/// (`exclude_unset=True` at the call site — verified directly against
/// inventory_service.update_product) only for fields genuinely present
/// in the request; ProductRepositoryImpl.updateProduct only ever
/// constructs one of these from the subset of arguments its own caller
/// actually passed, for exactly this reason.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false, includeIfNull: false)
class ProductUpdateDto {
  const ProductUpdateDto({
    this.name,
    this.sku,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.costPrice,
    this.sellingPrice,
    this.lowStockThreshold,
    this.isActive,
  });

  final String? name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final double? costPrice;
  final double? sellingPrice;
  final int? lowStockThreshold;
  final bool? isActive;

  Map<String, dynamic> toJson() => _$ProductUpdateDtoToJson(this);
}

/// A product joined with its stock count AT ONE SPECIFIC location —
/// the shape every product-list screen actually needs (Section 7a's
/// "joined in at query time rather than duplicating the whole product
/// row per location"). Not meaningful without a location in mind, which
/// is why ProductRepository's read methods all require one.
class ProductWithStock {
  const ProductWithStock({required this.product, required this.currentStock});

  final Product product;
  final int currentStock;

  /// Decision 18: "A product with tracking off never appears in Low
  /// Stock" — same exclusion `watchLowStockProducts`'s own query
  /// predicate applies (product_repository_impl.dart), needed here too
  /// since this getter is a second, independent place the same
  /// true/false answer gets computed. The two must be kept in sync by
  /// hand — there's no way to share one boolean expression between a SQL
  /// WHERE clause and a plain Dart getter.
  bool get isLowStock =>
      product.tracksStock && currentStock <= product.lowStockThreshold;
}

/// Mirrors backend/app/schemas/inventory.py's ProductOut exactly,
/// verified directly — the response body for POST /api/inventory/products,
/// PATCH .../products/{id}, and all three stock-movement endpoints
/// (.../stock-in, .../stock-out, .../adjust-stock all have
/// response_model=ProductOut, not a movement-record shape — verified
/// directly against routers/inventory.py). Lives here rather than in
/// stock_movements_api.dart specifically so it isn't duplicated the day
/// a real ProductsApi/ProductRepositoryImpl gets built — this is the one
/// shared, faithful wire-format mirror of ProductOut, matching where
/// CustomerResponseDto/ExpenseResponseDto/SaleResponseDto already live
/// (next to their own domain entity, not buried in whichever endpoint
/// file happened to need them first).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ProductResponseDto {
  const ProductResponseDto({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    this.categoryId,
    this.supplierId,
    required this.costPrice,
    required this.sellingPrice,
    required this.lowStockThreshold,
    required this.currentStock,
    required this.isActive,
    required this.isLowStock,
    required this.stockValue,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final double costPrice;
  final double sellingPrice;
  final int lowStockThreshold;
  final int currentStock;
  final bool isActive;
  final bool isLowStock;
  final double stockValue;

  factory ProductResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ProductResponseDtoFromJson(json);

  /// Was lossy with nowhere to reconcile currentStock/isLowStock/
  /// stockValue TO (see StockMovementsApi's own doc comment on the
  /// gap that created) until ProductRepositoryImpl existed — it still
  /// drops them here, but callers now have somewhere real to send them:
  /// ProductRepository.reconcileStockLevel (a single product) or
  /// .syncFromServer (the whole catalog) both write to
  /// ProductStockLevels directly from the raw ProductResponseDto,
  /// bypassing this lossy conversion entirely for that data. This
  /// method itself stays lossy on purpose — [Product] structurally has
  /// no field for stock, by design (see its own doc comment) — but the
  /// gap of "nowhere for the caller to put it" is closed.
  Product toDomain() {
    final now = DateTime.now();
    return Product(
      localId: id,
      serverId: id,
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      isActive: isActive,
      // Not present in ProductResponseDto — same caveat as every other
      // *ResponseDto._toDomain in this codebase (Customer/Expense/
      // Income): only ever correct for a response that just came
      // directly from a create/update call, not a general-purpose
      // server->domain mapping.
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// GET /api/inventory/products's response — mirrors backend's generic
/// PaginatedResponse[ProductOut] (app/schemas/common.py), verified
/// directly. No existing mobile precedent for a *paginated* list
/// response (AuthApi.getApprovalHashes's ApprovalHashesResponseDto is
/// the closest prior art for "a response wrapping a list," but that one
/// isn't paginated) — kept as a plain, non-generic DTO specific to
/// products rather than a generic PaginatedResponseDto<T>, since
/// json_serializable's code generation for generic wrapper types adds
/// real complexity for a pattern only one entity needs so far. If a
/// second paginated-list entity shows up, that's the point to
/// generalize this, not before.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ProductListResponseDto {
  const ProductListResponseDto({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<ProductResponseDto> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  factory ProductListResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ProductListResponseDtoFromJson(json);
}
