import '../entities/product.dart';

/// Repository contract for the local product catalog and per-location stock.
abstract class ProductRepository {
  Stream<List<ProductWithStock>> watchProducts({required String locationId});
  Future<ProductWithStock?> getProductById(String localId, {required String locationId});
  Future<ProductWithStock?> getProductByBarcode(String barcode, {required String locationId});
  Future<ProductWithStock?> getProductBySku(String sku, {required String locationId});
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId});
  Future<Set<String>> getAllSkus();
  Future<Set<String>> getAllBarcodes();
  Future<Product> createProduct(ProductDraft draft);
  Future<void> updateProduct({
    required String localId,
    String? name,
    String? sku,
    String? barcode,
    String? categoryId,
    String? supplierId,
    double? costPrice,
    double? sellingPrice,
    int? lowStockThreshold,
    bool? isActive,
  });
  Future<void> archiveProduct(String localId);
  Future<void> markSynced({required String localId, required String serverId});
  Future<void> syncFromServer();

  Future<void> reconcileStockLevel({
    required String productLocalId,
    required String locationId,
    required int currentStock,
  });

  /// Applies authoritative product state and all returned stock levels.
  /// This is inbound-only and must never enqueue an outbound sync task.
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    required String sku,
    String? barcode,
    String? categoryId,
    String? supplierId,
    required double costPrice,
    required double sellingPrice,
    required int lowStockThreshold,
    required bool isActive,
    required DateTime updatedAt,
    DateTime? deletedAt,
    required List<ProductStockSnapshot> stockLevels,
  });

  Future<void> reconcileDeleted(String serverId);

  Future<void> setLocalOverrides({
    required String productLocalId,
    bool? tracksStock,
    String? unit,
    String? photoPath,
  });
}
