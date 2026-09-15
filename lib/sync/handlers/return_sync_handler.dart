import 'package:drift/drift.dart';

import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/return_repository.dart';
import '../sync_handler.dart';

/// Pushes returns through the authoritative Fulus Cloud command API.
class ReturnSyncHandler implements SyncHandler {
  ReturnSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required ReturnRepository returnRepository,
  })  : _db = db,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _returnRepository = returnRepository;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final ReturnRepository _returnRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError('ReturnSyncHandler supports only create.');
    }
    final request = await _returnRepository.getReturnById(item.entityLocalId);
    if (request == null) throw StateError('No local return found for ${item.entityLocalId}.');
    if (request.serverId?.isNotEmpty == true) return;

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for return sync.');
    }

    final sale = await (_db.select(_db.sales)
          ..where((s) => s.localId.equals(request.originalSaleLocalId)))
        .getSingleOrNull();
    final saleId = sale?.serverId;
    if (saleId == null || saleId.isEmpty) {
      throw StateError('Return cannot sync before its original sale is synced.');
    }

    final rows = await (_db.select(_db.returnItems)
          ..where((r) => r.returnLocalId.equals(request.localId)))
        .get();
    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      final product = await (_db.select(_db.products)
            ..where((p) => p.localId.equals(row.productLocalId)))
          .getSingleOrNull();
      final productId = product?.serverId;
      if (productId == null || productId.isEmpty) {
        throw StateError('Return product ${row.productLocalId} has no server identity yet.');
      }
      items.add({'product_id': productId, 'quantity': row.quantity});
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'return.create',
      operationId: item.id,
      deviceClientId: device!.deviceClientId,
      clientReference: request.localId,
      payload: {
        'business_id': businessId,
        'sale_id': saleId,
        'operation_id': item.id,
        'reason': request.returnReason,
        'refund_amount': request.refundAmount,
        'refund_method': request.refundMethod,
        'items': items,
      },
    );
    final data = result['data'];
    if (data is! Map) throw StateError('Fulus return sync returned no response data.');
    final serverId = (data['entity_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) throw StateError('Fulus return sync returned no server entity ID.');
    await _returnRepository.markSynced(localId: request.localId, serverId: serverId);
  }
}
