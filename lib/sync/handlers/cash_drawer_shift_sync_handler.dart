import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/cash_drawer_shift_repository.dart';
import '../sync_handler.dart';

/// Syncs both lifecycle operations for a cash drawer shift through the
/// canonical Fulus Cloud transport.
class CashDrawerShiftSyncHandler implements SyncHandler {
  CashDrawerShiftSyncHandler({
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required CashDrawerShiftRepository cashDrawerShiftRepository,
  })  : _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _cashDrawerShiftRepository = cashDrawerShiftRepository;

  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final CashDrawerShiftRepository _cashDrawerShiftRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    switch (item.operation) {
      case 'create':
        await _syncCreate(item);
      case 'close':
        await _syncClose(item);
      default:
        throw StateError(
          'CashDrawerShiftSyncHandler does not support operation '
          '"${item.operation}".',
        );
    }
  }

  Future<void> _syncCreate(SyncQueueItem item) async {
    final shift = await _requireShift(item.entityLocalId);
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for cash drawer sync.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'cash_drawer_shift.create',
      operationId: item.id,
      clientReference: shift.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': shift.localId,
        'location_id': shift.locationId,
        'opening_cash': shift.openingCash,
        'opened_at': shift.openedAt.toIso8601String(),
      },
    );

    await _markSyncedFromResult(shift.localId, result);
  }

  Future<void> _syncClose(SyncQueueItem item) async {
    final shift = await _requireShift(item.entityLocalId);
    final serverId = shift.serverId;
    if (serverId == null || serverId.isEmpty) {
      throw StateError(
        'Cannot sync a shift close before its create has synced '
        '(no serverId yet for ${shift.localId}).',
      );
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for cash drawer sync.');
    }
    if (shift.closedAt == null || shift.closingCash == null) {
      throw StateError('Cannot sync an open cash drawer shift as closed.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'cash_drawer_shift.close',
      operationId: item.id,
      clientReference: shift.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': shift.localId,
        'shift_id': serverId,
        'closing_cash': shift.closingCash,
        'cash_difference': shift.cashDifference,
        'closing_note': shift.closingNote,
        'closed_at': shift.closedAt!.toIso8601String(),
      },
    );

    await _markSyncedFromResult(shift.localId, result);
  }

  Future<void> _markSyncedFromResult(
    String localId,
    Map<String, dynamic> result,
  ) async {
    final rawData = result['data'];
    if (rawData is! Map) {
      throw StateError('Fulus cash drawer sync returned no response data.');
    }
    final data = Map<String, dynamic>.from(rawData);
    final serverId = (data['entity_id'] ?? data['shift_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) {
      throw StateError('Fulus cash drawer sync returned no server entity ID.');
    }
    await _cashDrawerShiftRepository.markSynced(
      localId: localId,
      serverId: serverId,
    );
  }

  Future<CashDrawerShift> _requireShift(String localId) async {
    final shift = await _cashDrawerShiftRepository.getShiftById(localId);
    if (shift == null) {
      throw StateError(
        'No local shift found for $localId — the queue item outlived '
        'its own row.',
      );
    }
    return shift;
  }
}
