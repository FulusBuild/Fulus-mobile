import 'package:drift/drift.dart';

import '../../domain/entities/product.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

/// Domain -> Drift, for the local-write-first create in
/// ProductRepositoryImpl.createProduct — same shape as
/// CategoryToCompanion/SupplierToCompanion (syncStatus always `pending`
/// here; only ever used at creation time).
extension ProductToCompanion on Product {
  ProductsCompanion toDriftCompanion() {
    return ProductsCompanion.insert(
      localId: localId,
      name: name,
      sku: sku,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      supplierId: Value(supplierId),
      lowStockThreshold: Value(lowStockThreshold),
      isActive: Value(isActive),
      deletedAt: const Value(null),
    );
  }

  ProductCreateDto toCreateDto({required int initialStock}) {
    return ProductCreateDto(
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      initialStock: initialStock,
    );
  }

  /// Every field, not just whatever changed in the most recent local
  /// edit — see SyncTask.updateProduct's own doc comment for why that's
  /// the correct thing to send, not a simplification of it.
  ProductUpdateDto toUpdateDto() {
    return ProductUpdateDto(
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      isActive: isActive,
    );
  }
}

extension ProductRowToDomain on ProductRow {
  Product toDomain() {
    return Product(
      localId: localId,
      serverId: serverId,
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      isActive: isActive,
      tracksStock: tracksStock,
      unit: unit,
      photoPath: photoPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

extension ProductResponseDtoToCompanion on ProductResponseDto {
  /// Builds the Products (catalog) row directly from the raw response —
  /// there's no Draft/entity round-trip here the way write-first
  /// entities (Sale/Customer/Expense/IncomeRecord) have, since a Product
  /// only ever originates server-side. localId == id, matching every
  /// other *ResponseDto.toDomain in this codebase for the same reason
  /// (see ProductResponseDto.toDomain's own comment). syncStatus is
  /// always settled — this data only ever gets written here as a direct
  /// consequence of a successful server response, never speculatively
  /// ahead of one.
  ProductsCompanion toDriftCompanion() {
    final now = DateTime.now();
    return ProductsCompanion.insert(
      localId: id,
      serverId: Value(id),
      name: name,
      sku: sku,
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      supplierId: Value(supplierId),
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: Value(lowStockThreshold),
      isActive: Value(isActive),
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
      deletedAt: const Value(null),
    );
  }

  /// Builds the corresponding ProductStockLevels row for whichever
  /// [locationLocalId] the caller resolved (there's no location on
  /// ProductResponseDto itself — the backend has no location concept at
  /// all, see ProductRepositoryImpl's own doc comment on how the single
  /// local Location gets resolved for this phase).
  ProductStockLevelsCompanion toStockLevelCompanion({required String locationLocalId}) {
    return ProductStockLevelsCompanion.insert(
      productLocalId: id,
      locationLocalId: locationLocalId,
      currentStock: Value(currentStock),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.settled,
    );
  }
}
