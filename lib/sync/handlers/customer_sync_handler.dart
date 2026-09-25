import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/customer_repository.dart';
import '../sync_handler.dart';

/// Syncs customers through the Fulus Cloud transport when cloud sync is
/// configured. There is intentionally no silent fallback to the legacy API:
/// a queue item must have one authoritative cloud path.
class CustomerSyncHandler implements SyncHandler {
  CustomerSyncHandler({
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required CustomerRepository customerRepository,
  })  : _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _customerRepository = customerRepository;

  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final CustomerRepository _customerRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create' && item.operation != 'update') {
      throw StateError(
        'CustomerSyncHandler does not support this operation.',
      );
    }

    final customer = await _customerRepository.getCustomerById(item.entityLocalId);
    if (customer == null) {
      throw StateError('No local customer found for ${item.entityLocalId}.');
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for customer sync.');
    }

    final isUpdate = item.operation == 'update';
    final existingServerId = customer.serverId;
    if (isUpdate && (existingServerId == null || existingServerId.isEmpty)) {
      throw StateError(
        'Cannot sync customer update before its create has synced.',
      );
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: isUpdate ? 'customer.update' : 'customer.create',
      operationId: item.id,
      clientReference: customer.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': customer.localId,
        'name': customer.name,
        'phone': customer.phone,
        'email': customer.email,
        'address': customer.address,
        'notes': customer.notes,
        'credit_limit': customer.creditLimit ?? 0,
        if (isUpdate) 'server_id': existingServerId,
        if (isUpdate && item.baseCursor != null) 'base_cursor': item.baseCursor,
        if (isUpdate) 'is_active': customer.deletedAt == null,
      },
    );

    // Queue coalescing can leave an archived, never-synced customer on
    // the original create item. The cloud create contract creates active
    // customers, so complete that lifecycle with a second stable update.
    if (!isUpdate && customer.deletedAt != null) {
      final createData = result['data'];
      if (createData is! Map) {
        throw StateError('Fulus customer create returned no response data.');
      }
      final createMap = Map<String, dynamic>.from(createData);
      final serverId = (createMap['entity_id'] ?? createMap['customer_id']) as String?;
      if (serverId == null || serverId.isEmpty) {
        throw StateError('Fulus customer create returned no server entity ID.');
      }
      final archiveOperationId = '${item.id}:archive';
      final archiveResult = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'customer.update',
        operationId: archiveOperationId,
        clientReference: customer.localId,
        deviceClientId: device.deviceClientId,
        payload: {
          'business_id': businessId,
          'operation_id': archiveOperationId,
          'client_reference': customer.localId,
          'server_id': serverId,
          'name': customer.name,
          'phone': customer.phone,
          'email': customer.email,
          'address': customer.address,
          'notes': customer.notes,
          'credit_limit': customer.creditLimit ?? 0,
          'is_active': false,
        },
      );
      final archiveData = archiveResult['data'];
      if (archiveData is! Map) {
        throw StateError('Fulus customer archive returned no response data.');
      }
      final archiveMap = Map<String, dynamic>.from(archiveData);
      final archivedId = (archiveMap['entity_id'] ?? archiveMap['customer_id']) as String?;
      if (archivedId != serverId) {
        throw StateError('Fulus customer archive returned an unexpected entity ID.');
      }
    }

    final rawData = result['data'];
    if (rawData is! Map) {
      throw StateError('Fulus customer sync returned no response data.');
    }
    final data = Map<String, dynamic>.from(rawData);
    final serverId = (data['entity_id'] ?? data['customer_id']) as String?;
    if (serverId == null || serverId.isEmpty) {
      throw StateError('Fulus customer sync returned no server entity ID.');
    }

    await _customerRepository.markSynced(
      localId: customer.localId,
      serverId: serverId,
      duplicateWarning: data['duplicate_warning'] as String?,
    operationId: item.id,
    );
  }
}
