import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../remote/endpoints/products_api.dart';
import 'product_mapper.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({
    required AppDatabase db,
    required ProductsApi productsApi,
    required SyncQueue syncQueue,
  })  : _db = db,
        _productsApi = productsApi,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final ProductsApi _productsApi;
  final SyncQueue _syncQueue;

  ProductWithStock _mapRow(TypedResult row) {
    final product = row.readTable(_db.products);
    final stockLevel = row.readTableOrNull(_db.productStockLevels);
    return ProductWithStock(
      product: product.toDomain(),
      currentStock: stockLevel?.currentStock ?? 0,
    );
  }

  @override
  Stream<List<ProductWithStock>> watchProducts({required String locationId}) {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.deletedAt.isNull())
      ..where(_db.products.isActive.equals(true));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductById(
    String localId, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.localId.equals(localId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId}) {
    final query = _db.select(_db.products).join([
      innerJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.deletedAt.isNull())
      ..where(_db.products.isActive.equals(true))
      ..where(_db.products.tracksStock.equals(true))
      ..where(_db.productStockLevels.currentStock.isSmallerOrEqual(_db.products.lowStockThreshold));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductByBarcode(
    String barcode, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.barcode.equals(barcode) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<ProductWithStock?> getProductBySku(
    String sku, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.sku.equals(sku) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<Set<String>> getAllSkus() async {
    final rows = await (_db.selectOnly(_db.products)
          ..addColumns([_db.products.sku])
          ..where(_db.products.deletedAt.isNull()))
        .get();
    return rows.map((r) => r.read(_db.products.sku)!).toSet();
  }

  @override
  Future<Set<String>> getAllBarcodes() async {
    final rows = await (_db.selectOnly(_db.products)
          ..addColumns([_db.products.barcode])
          ..where(_db.products.deletedAt.isNull() & _db.products.barcode.isNotNull()))
        .get();
    return rows.map((r) => r.read(_db.products.barcode)!).toSet();
  }

  @override
  Future<void> syncFromServer() async {
    final location = await _db.select(_db.locations).getSingleOrNull();
    var page = 1;
    var totalPages = 1;
    do {
      final response = await _productsApi.listProducts(page: page);
      totalPages = response.totalPages;
      for (final item in response.items) {
        await _db.into(_db.products).insertOnConflictUpdate(item.toDriftCompanion());
        if (location != null) {
          await _db.into(_db.productStockLevels).insertOnConflictUpdate(
                item.toStockLevelCompanion(locationLocalId: location.localId),
              );
        }
      }
      page++;
    } while (page <= totalPages);
  }

  @override
  Future<void> reconcileStockLevel({
    required String productLocalId,
    required String locationId,
    required int currentStock,
  }) async {
    final product = await (_db.select(_db.products)
          ..where((p) => p.localId.equals(productLocalId)))
        .getSingleOrNull();
    if (product == null) {
      throw StateError(
        'reconcileStockLevel called for product $productLocalId, which this device has no local Products row for.',
      );
    }
    await _db.into(_db.productStockLevels).insertOnConflictUpdate(
          ProductStockLevelsCompanion.insert(
            productLocalId: productLocalId,
            locationLocalId: locationId,
            currentStock: Value(currentStock),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  @override
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
  }) async {
    final existing = await (_db.select(_db.products)
          ..where((p) => p.serverId.equals(serverId)))
        .getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();

    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                name: name,
                sku: sku,
                barcode: Value(barcode),
                categoryId: Value(categoryId),
                supplierId: Value(supplierId),
                costPrice: costPrice,
                sellingPrice: sellingPrice,
                lowStockThreshold: Value(lowStockThreshold),
                isActive: Value(isActive),
                createdAt: updatedAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: const Value(SyncStatus.settled),
              ),
            );
      } else {
        await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
          ProductsCompanion(
            serverId: Value(serverId),
            name: Value(name),
            sku: Value(sku),
            barcode: Value(barcode),
            categoryId: Value(categoryId),
            supplierId: Value(supplierId),
            costPrice: Value(costPrice),
            sellingPrice: Value(sellingPrice),
            lowStockThreshold: Value(lowStockThreshold),
            isActive: Value(isActive),
            deletedAt: Value(deletedAt),
            updatedAt: Value(updatedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }

      for (final stock in stockLevels) {
        final location = await (_db.select(_db.locations)
              ..where((l) => l.serverId.equals(stock.locationServerId)))
            .getSingleOrNull();
        if (location == null) {
          throw StateError(
            'Canonical product $serverId references unknown location ${stock.locationServerId}.',
          );
        }
        await _db.into(_db.productStockLevels).insertOnConflictUpdate(
              ProductStockLevelsCompanion.insert(
                productLocalId: localId,
                locationLocalId: location.localId,
                currentStock: Value(stock.currentStock),
                updatedAt: stock.updatedAt ?? updatedAt,
                syncStatus: SyncStatus.settled,
              ),
            );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.products)
          ..where((p) => p.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.products)..where((p) => p.localId.equals(row.localId))).write(
      ProductsCompanion(
        deletedAt: Value(now),
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<Product> createProduct(ProductDraft draft) async {
    if (draft.sellingPrice <= 0) {
      throw ArgumentError.value(draft.sellingPrice, 'sellingPrice', 'must be > 0');
    }
    if (draft.costPrice < 0) {
      throw ArgumentError.value(draft.costPrice, 'costPrice', 'must be >= 0');
    }
    final existingSku = await (_db.select(_db.products)..where((p) => p.sku.equals(draft.sku) & p.deletedAt.isNull())).getSingleOrNull();
    if (existingSku != null) throw ArgumentError.value(draft.sku, 'sku', 'already exists');
    if (draft.barcode != null && draft.barcode!.isNotEmpty) {
      final existingBarcode = await (_db.select(_db.products)..where((p) => p.barcode.equals(draft.barcode!) & p.deletedAt.isNull())).getSingleOrNull();
      if (existingBarcode != null) throw ArgumentError.value(draft.barcode, 'barcode', 'already exists');
    }
    final localId = Ulid().toString();
    final product = draft.toProductEntity(localId: localId);
    await _db.transaction(() async {
      await _db.into(_db.products).insert(product.toDriftCompanion());
      await reconcileStockLevel(
        productLocalId: localId,
        locationId: draft.locationId,
        currentStock: draft.initialStock,
      );
      await _syncQueue.enqueue(SyncTask.createProduct(localId));
    });
    return product;
  }

  @override
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
  }) async {
    if (sellingPrice != null && sellingPrice <= 0) {
      throw ArgumentError.value(sellingPrice, 'sellingPrice', 'must be > 0');
    }
    if (costPrice != null && costPrice < 0) {
      throw ArgumentError.value(costPrice, 'costPrice', 'must be >= 0');
    }
    final current = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (current == null) throw StateError('Product $localId does not exist.');
    if (sku != null) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.sku.equals(sku) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(sku, 'sku', 'already exists');
    }
    if (barcode != null && barcode.isNotEmpty) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.barcode.equals(barcode) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(barcode, 'barcode', 'already exists');
    }
    await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
      ProductsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        sku: sku == null ? const Value.absent() : Value(sku),
        barcode: barcode == null ? const Value.absent() : Value(barcode),
        categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
        supplierId: supplierId == null ? const Value.absent() : Value(supplierId),
        costPrice: costPrice == null ? const Value.absent() : Value(costPrice),
        sellingPrice: sellingPrice == null ? const Value.absent() : Value(sellingPrice),
        lowStockThreshold: lowStockThreshold == null ? const Value.absent() : Value(lowStockThreshold),
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        syncStatus: Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncQueue.enqueue(SyncTask.updateProduct(localId));
  }

  @override
  Future<void> archiveProduct(String localId) async {
    final now = DateTime.now();
    final row = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (row == null) throw StateError('Product $localId does not exist.');
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
        ProductsCompanion(
          deletedAt: Value(now),
          isActive: const Value(false),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateProduct(localId));
    });
  }

  @override
  Future<void> markSynced({required String localId, required String serverId}) async {
    await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
      ProductsCompanion(
        serverId: Value(serverId),
        syncStatus: Value(SyncStatus.settled),
      ),
    );
  }

  @override
  Future<void> setLocalOverrides({
    required String productLocalId,
    bool? tracksStock,
    String? unit,
    String? photoPath,
  }) async {
    await (_db.update(_db.products)..where((p) => p.localId.equals(productLocalId))).write(
      ProductsCompanion(
        tracksStock: tracksStock == null ? const Value.absent() : Value(tracksStock),
        unit: unit == null ? const Value.absent() : Value(unit),
        photoPath: photoPath == null ? const Value.absent() : Value(photoPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
