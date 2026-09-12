import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/sales_api.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/entities/sale.dart';
import '../../domain/repositories/sale_repository.dart';
import '../sync_handler.dart';

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

    final businessId = _fulusConnectionState?.selectedBusinessId;
    final device = _fulusConnectionState?.registeredDevice;
    if (_fulusSyncApi != null && businessId != null && device?.status == 'active') {
      final customerId = await _resolveCustomerServerId(sale);
      final items = await _resolveItems(sale);
      final result = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'sale.create',
        operationId: item.id,
        clientReference: sale.clientReference,
        deviceClientId: device!.deviceClientId,
        payload: {
          'business_id': businessId,
          'location_id': sale.locationId,
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

    final salesApi = _salesApi;
    if (salesApi == null) {
      throw StateError('Fulus cloud authorization is required for sale sync.');
    }
    final items = await _resolveItems(sale);
    final synced = await salesApi.createSale(
      dto: SaleCreateDto(
        clientReference: sale.clientReference,
        locationId: sale.locationId,
        customerId: sale.customerId,
        saleDate: sale.saleDate,
        discount: sale.discount,
        tax: sale.tax,
        amountPaid: sale.amountPaid,
        paymentMethod: sale.paymentMethod,
        notes: sale.notes,
        items: items
            .map((item) => SaleItemCreateDto(
                  productId: item['product_id'] as String,
                  quantity: item['quantity'] as int,
                  unitPrice: (item['unit_price'] as num).toDouble(),
                ))
            .toList(growable: false),
      ),
      locationLocalId: sale.locationId,
    );
    final syncedServerId = synced.serverId;
    if (syncedServerId == null) {
      throw StateError('Sales API returned no server ID for synced sale.');
    }
    await _saleRepository.markSynced(
      localId: sale.localId,
      serverId: syncedServerId,
      invoiceNumber: synced.invoiceNumber,
    );
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
        throw StateError('Sale item has no productLocalId.');
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
