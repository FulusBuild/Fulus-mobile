import 'package:drift/drift.dart';
import '../../core/money/money.dart';
import '../../core/utils/photo_path.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/product.dart';
import '../../domain/entities/product_stock_snapshot.dart';
import '../../domain/repositories/product_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'product_mapper.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  ProductWithStock _mapRow(TypedResult row) {
    final product = row.readTable(_db.products);
    final stockLevel = row.readTableOrNull(_db.productStockLevels);
    return ProductWithStock(product: product.toDomain(), currentStock: stockLevel?.currentStock ?? 0);
  }

  @override
  Stream<List<ProductWithStock>> watchProducts({required String locationId}) {
    final query = _db.select(_db.products).join([
      leftOuterJoin(_db.productStockLevels, _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) & _db.productStockLevels.locationLocalId.equals(locationId)),
    ])..where(_db.products.locationId.equals(locationId))..where(_db.products.deletedAt.isNull())..where(_db.products.isActive.equals(true));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductById(String localId, {required String locationId}) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(_db.productStockLevels, _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) & _db.productStockLevels.locationLocalId.equals(locationId)),
    ])..where(_db.products.localId.equals(localId))..where(_db.products.locationId.equals(locationId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId}) {
    final query = _db.select(_db.products).join([
      innerJoin(_db.productStockLevels, _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) & _db.productStockLevels.locationLocalId.equals(locationId)),
    ])..where(_db.products.locationId.equals(locationId))..where(_db.products.deletedAt.isNull())..where(_db.products.isActive.equals(true))..where(_db.products.tracksStock.equals(true))..where(_db.productStockLevels.currentStock.isSmallerOrEqual(_db.products.lowStockThreshold));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductByBarcode(String barcode, {required String locationId}) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(_db.productStockLevels, _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) & _db.productStockLevels.locationLocalId.equals(locationId)),
    ])..where(_db.products.locationId.equals(locationId) & _db.products.barcode.equals(barcode) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<ProductWithStock?> getProductBySku(String sku, {required String locationId}) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(_db.productStockLevels, _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) & _db.productStockLevels.locationLocalId.equals(locationId)),
    ])..where(_db.products.locationId.equals(locationId) & _db.products.sku.equals(sku) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  Future<void> _assertProductInActiveLocation(String? productLocationId) async {
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    if (session != null &&
        (session.activeLocationId == null ||
            productLocationId != session.activeLocationId)) {
      throw StateError('Product is outside the active location.');
    }
  }

  @override
  Future<Set<String>> getAllSkus() async {
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    final query = _db.selectOnly(_db.products)
      ..addColumns([_db.products.sku])
      ..where(_db.products.deletedAt.isNull());
    if (session != null) {
      final locationId = session.activeLocationId;
      if (locationId == null) return <String>{};
      query.where(_db.products.locationId.equals(locationId));
    }
    final rows = await query.get();
    return rows.map((row) => row.read(_db.products.sku)!).toSet();
  }

  @override
  Future<Set<String>> getAllBarcodes() async {
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    final query = _db.selectOnly(_db.products)
      ..addColumns([_db.products.barcode])
      ..where(_db.products.deletedAt.isNull() & _db.products.barcode.isNotNull());
    if (session != null) {
      final locationId = session.activeLocationId;
      if (locationId == null) return <String>{};
      query.where(_db.products.locationId.equals(locationId));
    }
    final rows = await query.get();
    return rows.map((row) => row.read(_db.products.barcode)!).toSet();
  }

  @override
  Future<void> reconcileStockLevel({required String productLocalId, required String locationId, required int currentStock, String? operationId}) async {
    await _db.transaction(() async {
      final product = await (_db.select(_db.products)..where((p) => p.localId.equals(productLocalId))).getSingleOrNull();
      if (product == null) throw StateError('reconcileStockLevel called for product $productLocalId, which this device has no local Products row for.');
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)..where((q) => q.id.equals(operationId))).getSingleOrNull();
        if (current == null) return;
        final movement = await (_db.select(_db.stockMovements)
              ..where((m) => m.localId.equals(current.entityLocalId)))
            .getSingleOrNull();
        if (movement == null) return;
        final newerQueueItems = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.entityType.equals('stock_movement'))
              ..where((q) => q.id.isNotIn([operationId]))
              ..where((q) => q.enqueuedAt.isBiggerOrEqualValue(current.enqueuedAt)))
            .get();
        for (final newerQueueItem in newerQueueItems) {
          final newerMovement = await (_db.select(_db.stockMovements)
                ..where((m) => m.localId.equals(newerQueueItem.entityLocalId))
                ..where((m) => m.productLocalId.equals(movement.productLocalId))
                ..where((m) => m.locationId.equals(movement.locationId)))
              .getSingleOrNull();
          if (newerMovement != null) return;
        }
      }
      await _db.into(_db.productStockLevels).insertOnConflictUpdate(ProductStockLevelsCompanion.insert(productLocalId: productLocalId, locationLocalId: locationId, currentStock: Value(currentStock), updatedAt: DateTime.now(), syncStatus: SyncStatus.settled));
    });
  }

  @override
  Future<void> reconcileServerState({required String serverId, required String name, required String sku, String? barcode, String? categoryId, String? supplierId, required Money costPrice, required Money sellingPrice, required int lowStockThreshold, required bool isActive, String? photoPath, required DateTime updatedAt, DateTime? deletedAt, required List<ProductStockSnapshot> stockLevels}) async {
    final existing = await (_db.select(_db.products)..where((p) => p.serverId.equals(serverId))).getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();
    // A photo that exists only on this device has not been uploaded yet. The
    // server knows nothing about it, so its (older or null) value must not
    // erase the local reference before the upload task has run.
    final String? effectivePhotoPath = isPendingLocalPhotoPath(existing?.photoPath) ? existing!.photoPath : photoPath;
    final localCategoryId = await _resolveCategoryLocalId(categoryId);
    final localSupplierId = await _resolveSupplierLocalId(supplierId);
    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.products).insert(ProductsCompanion.insert(localId: localId, serverId: Value(serverId), name: name, sku: sku, barcode: Value(barcode), categoryId: Value(localCategoryId), supplierId: Value(localSupplierId), costPrice: costPrice, sellingPrice: sellingPrice, lowStockThreshold: Value(lowStockThreshold), isActive: Value(isActive), photoPath: Value(effectivePhotoPath), createdAt: updatedAt, updatedAt: updatedAt, deletedAt: Value(deletedAt), syncStatus: SyncStatus.settled));
      } else {
        await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(ProductsCompanion(serverId: Value(serverId), name: Value(name), sku: Value(sku), barcode: Value(barcode), categoryId: Value(localCategoryId), supplierId: Value(localSupplierId), costPrice: Value(costPrice), sellingPrice: Value(sellingPrice), lowStockThreshold: Value(lowStockThreshold), isActive: Value(isActive), photoPath: Value(effectivePhotoPath), deletedAt: Value(deletedAt), updatedAt: Value(updatedAt), syncStatus: const Value(SyncStatus.settled)));
      }
      // stock_levels is authoritative: remove local rows that are absent from
      // the canonical aggregate, then restore exactly the server snapshot.
      await (_db.delete(_db.productStockLevels)..where((s) => s.productLocalId.equals(localId))).go();
      for (final stock in stockLevels) {
        final location = await (_db.select(_db.locations)..where((l) => l.serverId.equals(stock.locationServerId))).getSingleOrNull();
        if (location == null) throw StateError('Canonical product $serverId references unknown location ${stock.locationServerId}.');
        await _db.into(_db.productStockLevels).insertOnConflictUpdate(ProductStockLevelsCompanion.insert(productLocalId: localId, locationLocalId: location.localId, currentStock: Value(stock.currentStock), updatedAt: stock.updatedAt, syncStatus: SyncStatus.settled));
      }
    });
  }

  Future<String?> _resolveCategoryLocalId(String? id) async {
    if (id == null || id.isEmpty) return null;
    final local = await (_db.select(_db.categories)..where((c) => c.localId.equals(id))).getSingleOrNull();
    if (local != null) return local.localId;
    final server = await (_db.select(_db.categories)..where((c) => c.serverId.equals(id))).getSingleOrNull();
    return server?.localId;
  }

  Future<String?> _resolveSupplierLocalId(String? id) async {
    if (id == null || id.isEmpty) return null;
    final local = await (_db.select(_db.suppliers)..where((s) => s.localId.equals(id))).getSingleOrNull();
    if (local != null) return local.localId;
    final server = await (_db.select(_db.suppliers)..where((s) => s.serverId.equals(id))).getSingleOrNull();
    return server?.localId;
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.products)..where((p) => p.serverId.equals(serverId))).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.products)..where((p) => p.localId.equals(row.localId))).write(ProductsCompanion(deletedAt: Value(now), isActive: const Value(false), syncStatus: const Value(SyncStatus.settled), updatedAt: Value(now)));
  }

  @override
  Future<Product> createProduct(ProductDraft draft) async {
    if (draft.sellingPrice <= 0) throw ArgumentError.value(draft.sellingPrice, 'sellingPrice', 'must be > 0');
    if (draft.costPrice < 0) throw ArgumentError.value(draft.costPrice, 'costPrice', 'must be >= 0');
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    if (session != null && session.activeLocationId != draft.locationId) {
      throw StateError('Products can only be created in the active location.');
    }
    final existingSku = await (_db.select(_db.products)
          ..where((p) => p.sku.equals(draft.sku) &
              p.locationId.equals(draft.locationId) &
              p.deletedAt.isNull()))
        .getSingleOrNull();
    if (existingSku != null) throw ArgumentError.value(draft.sku, 'sku', 'already exists');
    if (draft.barcode != null && draft.barcode!.isNotEmpty) {
      final existingBarcode = await (_db.select(_db.products)
            ..where((p) => p.barcode.equals(draft.barcode!) &
                p.locationId.equals(draft.locationId) &
                p.deletedAt.isNull()))
          .getSingleOrNull();
      if (existingBarcode != null) throw ArgumentError.value(draft.barcode, 'barcode', 'already exists');
    }
    final localId = Ulid().toString();
    final product = draft.toProductEntity(localId: localId);
    await _db.transaction(() async {
      await _db.into(_db.products).insert(product.toDriftCompanion());
      await reconcileStockLevel(productLocalId: localId, locationId: draft.locationId, currentStock: draft.initialStock);
      await _syncQueue.enqueue(SyncTask.createProduct(localId));
    });
    return product;
  }

  @override
  Future<void> updateProduct({required String localId, String? name, String? sku, String? barcode, String? categoryId, String? supplierId, Money? costPrice, Money? sellingPrice, int? lowStockThreshold, bool? isActive, String? photoPath, bool clearPhoto = false}) async {
    if (sellingPrice != null && sellingPrice <= 0) throw ArgumentError.value(sellingPrice, 'sellingPrice', 'must be > 0');
    if (costPrice != null && costPrice < 0) throw ArgumentError.value(costPrice, 'costPrice', 'must be >= 0');
    final current = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (current == null) throw StateError('Product $localId does not exist.');
    await _assertProductInActiveLocation(current.locationId);
    if (sku != null) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.sku.equals(sku) & p.locationId.equals(current.locationId) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(sku, 'sku', 'already exists');
    }
    if (barcode != null && barcode.isNotEmpty) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.barcode.equals(barcode) & p.locationId.equals(current.locationId) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(barcode, 'barcode', 'already exists');
    }
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(ProductsCompanion(name: name == null ? const Value.absent() : Value(name), sku: sku == null ? const Value.absent() : Value(sku), barcode: barcode == null ? const Value.absent() : Value(barcode), categoryId: categoryId == null ? const Value.absent() : Value(categoryId), supplierId: supplierId == null ? const Value.absent() : Value(supplierId), costPrice: costPrice == null ? const Value.absent() : Value(costPrice), sellingPrice: sellingPrice == null ? const Value.absent() : Value(sellingPrice), lowStockThreshold: lowStockThreshold == null ? const Value.absent() : Value(lowStockThreshold), isActive: isActive == null ? const Value.absent() : Value(isActive), photoPath: clearPhoto ? const Value<String?>(null) : (photoPath == null ? const Value.absent() : Value(photoPath)), syncStatus: Value(SyncStatus.pending), updatedAt: Value(DateTime.now())));
      await _syncQueue.enqueue(SyncTask.updateProduct(localId));
      await _syncPhotoTask(localId, photoPath: photoPath, clearPhoto: clearPhoto);
    });
  }

  @override
  Future<void> archiveProduct(String localId) async {
    final now = DateTime.now();
    final row = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (row == null) throw StateError('Product $localId does not exist.');
    await _assertProductInActiveLocation(row.locationId);
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(ProductsCompanion(deletedAt: Value(now), isActive: const Value(false), updatedAt: Value(now), syncStatus: const Value(SyncStatus.pending)));
      await _syncQueue.enqueue(SyncTask.updateProduct(localId));
    });
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? operationId,
  }) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (current == null) {
          // A missing operation row means this completion is stale. Never
          // allow an old network response to settle a mutation whose queue
          // identity is no longer present.
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'product',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
        ProductsCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> setLocalOverrides({required String productLocalId, bool? tracksStock, String? unit, String? photoPath, bool clearPhoto = false}) async {
    final row = await (_db.select(_db.products)
          ..where((product) => product.localId.equals(productLocalId)))
        .getSingleOrNull();
    if (row == null) throw StateError('Product $productLocalId does not exist.');
    await _assertProductInActiveLocation(row.locationId);
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.localId.equals(productLocalId))).write(ProductsCompanion(tracksStock: tracksStock == null ? const Value.absent() : Value(tracksStock), unit: unit == null ? const Value.absent() : Value(unit), photoPath: clearPhoto ? const Value<String?>(null) : (photoPath == null ? const Value.absent() : Value(photoPath)), updatedAt: Value(DateTime.now())));
      await _syncPhotoTask(productLocalId, photoPath: photoPath, clearPhoto: clearPhoto);
      if (clearPhoto) {
        // Clearing a local photo is also a cloud mutation: without this update,
        // canonical reconciliation could restore the previous remote URL.
        await _syncQueue.enqueue(SyncTask.updateProduct(productLocalId));
      }
    });
  }

  /// Keeps the photo upload queue consistent with the product row, inside the
  /// caller's transaction: a device-local photo queues exactly one upload, and
  /// removing a photo cancels any upload that has not run yet. A cloud URL needs
  /// no upload.
  Future<void> _syncPhotoTask(String localId, {String? photoPath, required bool clearPhoto}) async {
    if (clearPhoto) {
      await (_db.delete(_db.syncQueueItems)
            ..where((q) => q.entityType.equals('product_photo'))
            ..where((q) => q.entityLocalId.equals(localId)))
          .go();
      return;
    }
    if (isPendingLocalPhotoPath(photoPath)) {
      await _syncQueue.enqueue(SyncTask.uploadProductPhoto(localId));
    }
  }
}
