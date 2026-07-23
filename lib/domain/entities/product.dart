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
