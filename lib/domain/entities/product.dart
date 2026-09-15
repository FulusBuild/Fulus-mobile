import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

/// Mirrors the Products table exactly — catalog fields only.
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
  final bool tracksStock;
  final String unit;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

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

class ProductWithStock {
  const ProductWithStock({required this.product, required this.currentStock});

  final Product product;
  final int currentStock;

  bool get isLowStock =>
      product.tracksStock && currentStock <= product.lowStockThreshold;
}

/// Authoritative stock state returned with a canonical product aggregate.
/// The location identifier is the server location ID and must be resolved
/// to the local Locations.localId before it is written to ProductStockLevels.
class ProductStockSnapshot {
  const ProductStockSnapshot({
    required this.locationServerId,
    required this.currentStock,
    this.updatedAt,
  });

  final String locationServerId;
  final int currentStock;
  final DateTime? updatedAt;
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: true)
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

  Map<String, dynamic> toJson() => _$ProductResponseDtoToJson(this);

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
      createdAt: now,
      updatedAt: now,
    );
  }
}

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
