import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/repositories/sale_repository.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';

class SaleSyncHandler implements SyncHandler {
  SaleSyncHandler({
    required AppDatabase db,
    FulusSyncApi? fulusSyncApi,
    FulusConnectionState? fulusConnectionState,
    required SaleRepository saleRepository,
    SalesApi? salesApi,
  })  : _db = db,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _saleRepository = saleRepository,
        _salesApi = salesApi;

  final AppDatabase _db;
  final FulusSyncApi? _fulusSyncApi;
  final FulusConnectionState? _fulusConnectionState;
  final SaleRepository _saleRepository;
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
      final result = await _fulusSyncApi.submitOperation(
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
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final serverId = data['entity_id'] as String?;
      if (serverId == null) {
        throw StateError('Fulus sale sync returned no server entity ID.');
      }
      await _saleRepository.markSynced(
        localId: sale.localId,
        serverId: serverId,
        invoiceNumber: data['invoice_number'] as String? ?? sale.clientReference,
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
