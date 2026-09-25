import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../data/remote/fulus_product_canonical_reconciler.dart';
import '../../data/remote/fulus_customer_canonical_reconciler.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../core/errors/failure.dart';
import '../../domain/repositories/return_repository.dart';
import '../sync_handler.dart';
import '../sync_execution_lease.dart';

/// Pushes returns through the authoritative Fulus Cloud command API.
class ReturnSyncHandler implements SyncHandler {
  ReturnSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required SyncExecutionLease executionLease,
    required FulusConnectionState fulusConnectionState,
    required ReturnRepository returnRepository,
    ProductRepository? productRepository,
    CustomerRepository? customerRepository,
  })  : _db = db,
        _executionLease = executionLease,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _returnRepository = returnRepository,
        _productRepository = productRepository,
        _customerRepository = customerRepository;
  final SyncExecutionLease _executionLease;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final ReturnRepository _returnRepository;
  final ProductRepository? _productRepository;
  final CustomerRepository? _customerRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') throw StateError('ReturnSyncHandler supports only create.');
    final request = await _returnRepository.getReturnById(item.entityLocalId);
    if (request == null) throw StateError('No local return found for ${item.entityLocalId}.');
    if (request.serverId?.isNotEmpty == true) return;
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for return sync.');
    }
    final sale = await (_db.select(_db.sales)..where((s) => s.localId.equals(request.originalSaleLocalId))).getSingleOrNull();
    final saleId = sale?.serverId;
    if (saleId == null || saleId.isEmpty) throw StateError('Return cannot sync before its original sale is synced.');
    final rows = await (_db.select(_db.returnItems)..where((r) => r.returnLocalId.equals(request.localId))).get();
    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      final product = await (_db.select(_db.products)..where((p) => p.localId.equals(row.productLocalId))).getSingleOrNull();
      final productId = product?.serverId;
      if (productId == null || productId.isEmpty) throw StateError('Return product ${row.productLocalId} has no server identity yet.');
      items.add({'product_id': productId, 'quantity': row.quantity});
    }
    late final Map<String, dynamic> result;
    try {
      result = await _fulusSyncApi.submitOperation(
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
    } on BusinessRuleFailure {
      await _reconcileAfterRejectedReturn(
        request: request,
        sale: sale,
        deviceClientId: device!.deviceClientId,
        businessId: businessId,
        operationId: item.id,
        enqueuedAt: item.enqueuedAt,
      );
      rethrow;
    }
    final data = result['data'];
    if (data is! Map) throw StateError('Fulus return sync returned no response data.');
    final serverId = (data['entity_id'] ?? data['return_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) throw StateError('Fulus return sync returned no server entity ID.');
    await _returnRepository.markSynced(localId: request.localId, serverId: serverId, operationId: item.id);
  }
  /// A return is completed locally before cloud delivery. If the cloud
  /// rejects it, restore local projections from authoritative product/customer
  /// snapshots before leaving the outbox item blocked.
  Future<void> _reconcileAfterRejectedReturn({
    required dynamic request,
    required dynamic sale,
    required String deviceClientId,
    required String businessId,
    required String operationId,
    required DateTime enqueuedAt,
  }) async {
    final productRepository = _productRepository;
    if (productRepository != null) {
      final reconciler =
          FulusProductCanonicalReconciler(repository: productRepository);
      final rows = await (_db.select(_db.returnItems)
            ..where((r) => r.returnLocalId.equals(request.localId)))
          .get();
      for (final localId in rows.map((row) => row.productLocalId).toSet()) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.localId.equals(localId)))
            .getSingleOrNull();
        final serverId = product?.serverId;
        if (serverId == null || serverId.isEmpty) continue;
        try {
          final canonical = await _fulusSyncApi.fetchCanonicalEntity(
            businessId: businessId,
            entityType: 'product',
            entityId: serverId,
            deviceClientId: deviceClientId,
          );
          await _executionLease.runProtectedTransaction(_db, () async {
            if (await _executionLease.hasNewerQueueMutation(
              entityType: 'product',
              entityLocalId: localId,
              operationId: operationId,
              enqueuedAt: enqueuedAt,
            )) return;
            await reconciler.apply(canonical);
          });
        } catch (_) {}
      }
    }

    final customerRepository = _customerRepository;
    final customerLocalId = sale.customerId as String?;
    if (customerRepository != null && customerLocalId != null) {
      final customer = await (_db.select(_db.customers)
            ..where((c) => c.localId.equals(customerLocalId)))
          .getSingleOrNull();
      final serverId = customer?.serverId;
      if (serverId != null && serverId.isNotEmpty) {
        try {
          final canonical = await _fulusSyncApi.fetchCanonicalEntity(
            businessId: businessId,
            entityType: 'customer',
            entityId: serverId,
            deviceClientId: deviceClientId,
          );
          await _executionLease.runProtectedTransaction(
            _db,
            () async {
              if (await _executionLease.hasNewerQueueMutation(
                entityType: 'customer',
                entityLocalId: customerLocalId,
                operationId: operationId,
                enqueuedAt: enqueuedAt,
              )) return;
              await FulusCustomerCanonicalReconciler(repository: customerRepository).apply(canonical);
            },
          );
        } catch (_) {}
      }
    }
  }

}
