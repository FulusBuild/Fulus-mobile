import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/fulus_product_canonical_reconciler.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';
import 'package:fulus_mobile/data/remote/fulus_customer_canonical_reconciler.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/repositories/sale_repository.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

class SaleSyncHandler implements SyncHandler {
  SaleSyncHandler({
    required AppDatabase db,
    FulusSyncApi? fulusSyncApi,
    required SyncExecutionLease executionLease,
    FulusConnectionState? fulusConnectionState,
    required SaleRepository saleRepository,
    ProductRepository? productRepository,
    CustomerRepository? customerRepository,
    SalesApi? salesApi,
  })  : _db = db,
        _executionLease = executionLease,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _saleRepository = saleRepository,
        _productRepository = productRepository,
        _customerRepository = customerRepository,
        _salesApi = salesApi;
  final SyncExecutionLease _executionLease;

  final AppDatabase _db;
  final FulusSyncApi? _fulusSyncApi;
  final FulusConnectionState? _fulusConnectionState;
  final SaleRepository _saleRepository;
  final ProductRepository? _productRepository;
  final CustomerRepository? _customerRepository;
  // Retained for injection compatibility with existing callers/tests. It is
  // intentionally never used for writes: queued sales are Fulus Cloud-only.
  final SalesApi? _salesApi;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError('SaleSyncHandler supports only create.');
    }
    final sale = await _saleRepository.getSaleByLocalId(item.entityLocalId);
    if (sale == null) {
      throw StateError('No local sale found for ${item.entityLocalId}.');
    }

    if (sale.customerId != null) {
      await _resolveCustomerServerId(sale);
    }

    final businessId = _fulusConnectionState?.selectedBusinessId;
    final device = _fulusConnectionState?.registeredDevice;
    if (_fulusSyncApi != null && businessId != null && device?.status == 'active') {
      final customerId = await _resolveCustomerServerId(sale);
      final locationId = await _resolveLocationServerId(sale.locationId);
      final items = await _resolveItems(sale);
      late final Map<String, dynamic> result;
      try {
        result = await _fulusSyncApi.submitOperation(
          businessId: businessId,
          operationType: 'sale.create',
          operationId: item.id,
          clientReference: sale.clientReference,
          deviceClientId: device!.deviceClientId,
          payload: {
            'business_id': businessId,
            'location_id': locationId,
            'customer_id': customerId,
            'client_reference': sale.clientReference,
            'sale_date': sale.saleDate.toIso8601String(),
            'discount': sale.discount,
            'tax': sale.tax,
            'amount_paid': sale.amountPaid,
            'payment_method': sale.paymentMethod,
            'notes': sale.notes,
            'items': items,
          },
        );
      } on BusinessRuleFailure {
        // The local sale optimistically decrements stock before cloud
        // delivery. A permanent cloud rejection (for example, another
        // device sold the last units first) therefore cannot simply leave
        // that optimistic projection in place. Re-read the authoritative
        // product snapshots before parking the sale so local stock does not
        // remain permanently below the server.
        await _reconcileProductsAfterRejectedSale(
          sale,
          device!.deviceClientId,
          businessId,
          operationId: item.id,
          enqueuedAt: item.enqueuedAt,
        );
        await _reconcileCustomerAfterRejectedSale(
          sale,
          device.deviceClientId,
          businessId,
          operationId: item.id,
          enqueuedAt: item.enqueuedAt,
        );
        rethrow;
      }
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final serverId = data['entity_id'] as String?;
      if (serverId == null) {
        throw StateError('Fulus sale sync returned no server entity ID.');
      }
      await _saleRepository.markSynced(
        localId: sale.localId,
        serverId: serverId,
        invoiceNumber: data['invoice_number'] as String? ?? sale.clientReference,
      operationId: item.id,
      );
      return;
    }

    final legacyTransportConfigured = _salesApi != null;
    throw SyncFailure(
      kind: SyncErrorKind.dependencyNotReady,
      message: legacyTransportConfigured
          ? 'Fulus Cloud authorization is required for sale sync; legacy API transport is disabled.'
          : 'Fulus Cloud authorization is required for sale sync.',
    );
  }

  Future<void> _reconcileProductsAfterRejectedSale(
    Sale sale,
    String deviceClientId,
    String businessId, {
    required String operationId,
    required DateTime enqueuedAt,
  }) async {
    final repository = _productRepository;
    if (repository == null) return;
    final reconciler = FulusProductCanonicalReconciler(repository: repository);
    final productIds = sale.items
        .map((item) => item.productLocalId)
        .whereType<String>()
        .toSet();
    for (final localId in productIds) {
      final product = await (_db.select(_db.products)
            ..where((p) => p.localId.equals(localId)))
          .getSingleOrNull();
      final serverId = product?.serverId;
      if (serverId == null || serverId.isEmpty) continue;
      try {
        final canonical = await _fulusSyncApi!.fetchCanonicalEntity(
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
          final newerMovements = await (_db.select(_db.syncQueueItems)
                ..where((q) => q.entityType.equals('stock_movement'))
                ..where((q) => q.id.isNotIn([operationId]))
                ..where((q) => q.enqueuedAt.isBiggerThanValue(enqueuedAt)))
              .get();
          for (final queued in newerMovements) {
            final movement = await (_db.select(_db.stockMovements)
                  ..where((m) => m.localId.equals(queued.entityLocalId))
                  ..where((m) => m.productLocalId.equals(localId))
                  ..where((m) => m.locationId.equals(sale.locationId)))
                .getSingleOrNull();
            if (movement != null) return;
          }
          await reconciler.apply(canonical);
        });
      } catch (_) {
        // The original business-rule rejection remains the meaningful
        // queue failure. A failed best-effort reconciliation must not hide
        // it or turn a deterministic rejection into a generic error.
      }
    }
  }

  Future<void> _reconcileCustomerAfterRejectedSale(
    Sale sale,
    String deviceClientId,
    String businessId, {
    required String operationId,
    required DateTime enqueuedAt,
  }) async {
    final repository = _customerRepository;
    final localId = sale.customerId;
    if (repository == null || localId == null) return;
    final customer = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    final serverId = customer?.serverId;
    if (serverId == null || serverId.isEmpty) return;
    try {
      final canonical = await _fulusSyncApi!.fetchCanonicalEntity(
        businessId: businessId,
        entityType: 'customer',
        entityId: serverId,
        deviceClientId: deviceClientId,
      );
      final reconciler = FulusCustomerCanonicalReconciler(repository: repository);
      await _executionLease.runProtectedTransaction(_db, () async {
        if (await _executionLease.hasNewerQueueMutation(
          entityType: 'customer',
          entityLocalId: localId,
          operationId: operationId,
          enqueuedAt: enqueuedAt,
        )) return;
        final newerRepayments = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.entityType.equals('customer_ledger'))
              ..where((q) => q.id.isNotIn([operationId]))
              ..where((q) => q.enqueuedAt.isBiggerThanValue(enqueuedAt)))
            .get();
        for (final queued in newerRepayments) {
          final ledger = await (_db.select(_db.customerLedgerEntries)
                ..where((e) => e.localId.equals(queued.entityLocalId))
                ..where((e) =>
                    e.customerLocalId.equals(localId).and(e.entryType.equals('repayment'))))
              .getSingleOrNull();
          if (ledger != null) return;
        }
        await reconciler.apply(canonical);
      });
    } catch (_) {}
  }

  Future<String> _resolveLocationServerId(String localId) async {
    final location = await (_db.select(_db.locations)
          ..where((l) => l.localId.equals(localId)))
        .getSingleOrNull();
    final serverId = location?.serverId;
    if (serverId == null || serverId.isEmpty) {
      throw StateError('Location $localId has no serverId yet.');
    }
    return serverId;
  }

  Future<String?> _resolveCustomerServerId(Sale sale) async {
    if (sale.customerId == null) return null;
    final customer = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(sale.customerId!)))
        .getSingleOrNull();
    final serverId = customer?.serverId;
    if (serverId == null) {
      throw StateError('Customer ${sale.customerId} has no serverId yet.');
    }
    return serverId;
  }

  Future<List<Map<String, dynamic>>> _resolveItems(Sale sale) async {
    final items = <Map<String, dynamic>>[];
    for (final line in sale.items) {
      final localProductId = line.productLocalId;
      if (localProductId == null) {
        final description = line.description.trim();
        if (description.isEmpty) {
          throw StateError('Quick Sale item has no description.');
        }
        items.add({
          'product_id': null,
          'description': description,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'cost_price_at_sale': line.costPriceAtSale,
        });
        continue;
      }
      final product = await (_db.select(_db.products)
            ..where((p) => p.localId.equals(localProductId)))
          .getSingleOrNull();
      final productId = product?.serverId;
      if (productId == null) {
        throw StateError('Product $localProductId has no serverId yet.');
      }
      items.add({
        'product_id': productId,
        'quantity': line.quantity,
        'unit_price': line.unitPrice,
      });
    }
    return items;
  }
}
