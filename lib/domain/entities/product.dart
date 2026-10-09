import 'package:json_annotation/json_annotation.dart';
import 'package:fulus_mobile/core/money/money.dart';

part 'product.g.dart';

/// Mirrors the Products table exactly — catalog fields only.
class Product {
  const Product({
    required this.localId,
    this.serverId,
    this.locationId,
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
  /// Null only for legacy catalog rows awaiting safe ownership reconciliation.
  final String? locationId;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  @MoneyJsonConverter()
  final Money costPrice;
  @MoneyJsonConverter()
  final Money sellingPrice;
  final String? locationId;
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
    this.photoPath,
  });

  final String name;
  final String sku;
  @MoneyJsonConverter()
  final Money costPrice;
  @MoneyJsonConverter()
  final Money sellingPrice;
  final String locationId;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final int lowStockThreshold;
  final int initialStock;
  final String? photoPath;

  Product toProductEntity({required String localId}) {
    final now = DateTime.now();
    return Product(
      localId: localId,
      locationId: locationId,
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
      photoPath: photoPath,
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
    this.locationId,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.lowStockThreshold = 10,
    this.initialStock = 0,
    this.photoPath,
  });

  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  @MoneyJsonConverter()
  final Money costPrice;
  @MoneyJsonConverter()
  final Money sellingPrice;
  final int lowStockThreshold;
  final int initialStock;
  final String? photoPath;

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
    this.photoPath,
  });

  final String? name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  @MoneyJsonConverter()
  final Money? costPrice;
  @MoneyJsonConverter()
  final Money? sellingPrice;
  final int? lowStockThreshold;
  final bool? isActive;
  final String? photoPath;

  Map<String, dynamic> toJson() => _$ProductUpdateDtoToJson(this);
}

class ProductWithStock {
  const ProductWithStock({required this.product, required this.currentStock});

  final Product product;
  final int currentStock;

  bool get isLowStock =>
      product.tracksStock && currentStock <= product.lowStockThreshold;
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
    this.locationId,
    this.photoPath,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  @MoneyJsonConverter()
  final Money costPrice;
  @MoneyJsonConverter()
  final Money sellingPrice;
  final String? locationId;
  final int lowStockThreshold;
  final int currentStock;
  final bool isActive;
  final bool isLowStock;
  @MoneyJsonConverter()
  final Money stockValue;
  final String? photoPath;

  factory ProductResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ProductResponseDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ProductResponseDtoToJson(this);

  Product toDomain() {
    final now = DateTime.now();
    return Product(
      localId: id,
      serverId: id,
      locationId: locationId,
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
      photoPath: photoPath,
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

  factory ProductListResponseDto.fromJson(Map<String, dynamic> json) {
    // Some deployed inventory responses encode an empty collection as null.
    // Normalize that wire representation at the DTO boundary so generated
    // json_serializable code never attempts to cast null to List<dynamic>.
    final normalized = <String, dynamic>{...json};
    if (normalized['items'] == null) normalized['items'] = const <dynamic>[];
    return _$ProductListResponseDtoFromJson(normalized);
  }
}
