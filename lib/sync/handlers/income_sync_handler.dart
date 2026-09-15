import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/income_record_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../sync_handler.dart';

/// Syncs miscellaneous income through the canonical Fulus Cloud transport.
class IncomeSyncHandler implements SyncHandler {
  IncomeSyncHandler({
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required IncomeRecordRepository incomeRecordRepository,
    required LocationRepository locationRepository,
  })  : _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _incomeRecordRepository = incomeRecordRepository,
        _locationRepository = locationRepository;

  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final IncomeRecordRepository _incomeRecordRepository;
  final LocationRepository _locationRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'IncomeSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final record = await _incomeRecordRepository.getIncomeRecordById(item.entityLocalId);
    if (record == null) {
      throw StateError(
        'No local income record found for ${item.entityLocalId} — the '
        'queue item outlived its own row.',
      );
    }

    final location = await _locationRepository.getLocationById(record.locationId);
    if (location == null || location.serverId?.isNotEmpty != true) {
      throw StateError(
        'Income cannot sync because location ${record.locationId} has not synced yet.',
      );
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for income sync.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'income.create',
      operationId: item.id,
      clientReference: record.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': record.localId,
        'location_id': location.serverId,
        'source': record.source,
        'amount': record.amount,
        'income_date': record.incomeDate.toIso8601String(),
        'notes': record.notes,
      },
    );

    final rawData = result['data'];
    if (rawData is! Map) {
      throw StateError('Fulus income sync returned no response data.');
    }
    final data = Map<String, dynamic>.from(rawData);
    final serverId = (data['entity_id'] ?? data['income_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) {
      throw StateError('Fulus income sync returned no server entity ID.');
    }

    await _incomeRecordRepository.markSynced(
      localId: record.localId,
      serverId: serverId,
    );
  }
}
