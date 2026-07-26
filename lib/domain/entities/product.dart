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
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
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

  bool get isLowStock => currentStock <= product.lowStockThreshold;
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
