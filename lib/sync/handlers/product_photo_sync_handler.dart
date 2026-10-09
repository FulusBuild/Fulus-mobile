import 'dart:io';


import '../../core/utils/photo_path.dart';
import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/product_image_api.dart';
import '../../domain/repositories/product_repository.dart';
import '../sync_error.dart';
import '../sync_handler.dart';

/// Uploads a product's device-local photo to Storage, then queues a normal
/// product update that carries the resulting cloud URL.
///
/// This is deliberately separate from [ProductSyncHandler]: a slow, oversized
/// or rejected photo can only ever affect this low-priority item. Product
/// data, stock and sales keep syncing around it.
class ProductPhotoSyncHandler implements SyncHandler {
  ProductPhotoSyncHandler({
    required AppDatabase db,
    required ProductRepository productRepository,
    required FulusConnectionState fulusConnectionState,
    required ProductImageApi productImageApi,
  })  : _db = db,
        _productRepository = productRepository,
        _fulusConnectionState = fulusConnectionState,
        _productImageApi = productImageApi;

  final AppDatabase _db;
  final ProductRepository _productRepository;
  final FulusConnectionState _fulusConnectionState;
  final ProductImageApi _productImageApi;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'upload') {
      throw StateError(
        'ProductPhotoSyncHandler does not support operation "${item.operation}".',
      );
    }
    final localId = item.entityLocalId;
    final row = await _findRow(localId);

    // Nothing left to do: product gone or archived, photo removed, or the
    // photo already holds a cloud URL.
    if (row == null || row.deletedAt != null) return;
    final path = row.photoPath;
    if (!isPendingLocalPhotoPath(path)) return;

    // The cloud URL must travel through a product update, which needs the
    // product's server identity. Defer until the create has synced.
    if (row.serverId == null || row.serverId!.isEmpty) {
      throw const SyncFailure(
        kind: SyncErrorKind.dependencyNotReady,
        message: 'Product photo is waiting for the product to reach Fulus Cloud.',
      );
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || device == null || device.status != 'active') {
      throw const SyncFailure(
        kind: SyncErrorKind.dependencyNotReady,
        message: 'Fulus cloud authorization is required for product photo sync.',
      );
    }

    final file = File(path!);
    if (!await file.exists()) {
      // The file is gone (cleared storage, restored database). Nothing can be
      // uploaded, so drop the dead local reference instead of retrying forever.
      await _productRepository.setLocalOverrides(
        productLocalId: localId,
        clearPhoto: true,
      );
      return;
    }

    final url = await _productImageApi.upload(
      file: file,
      businessId: businessId,
      productLocalId: localId,
    );

    // The user may have replaced or removed the photo while the upload ran.
    // Only publish the URL if the row still points at the file we uploaded;
    // otherwise a newer photo task (or the removal) owns the outcome.
    await _db.transaction(() async {
      final latest = await _findRow(localId);
      if (latest == null || latest.deletedAt != null) {
        return;
      }
      if (latest.photoPath != path) {
        // A replacement may have been selected while this upload was running.
        // The repository cannot replace the in-flight queue row because it is
        // still present, so retire this row and guarantee a fresh upload task.
        await (_db.delete(_db.syncQueueItems)
              ..where((q) => q.id.equals(item.id)))
            .go();
        if (isPendingLocalPhotoPath(latest.photoPath)) {
          await _productRepository.setLocalOverrides(
            productLocalId: localId,
            photoPath: latest.photoPath,
          );
        }
        return;
      }
      await _productRepository.updateProduct(localId: localId, photoPath: url);
    });
  }

  Future<ProductRow?> _findRow(String localId) {
    return (_db.select(_db.products)..where((p) => p.localId.equals(localId)))
        .getSingleOrNull();
  }
}

