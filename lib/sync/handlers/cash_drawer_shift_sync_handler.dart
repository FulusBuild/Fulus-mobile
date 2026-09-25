import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/entities/cash_drawer_shift.dart';
import '../../domain/repositories/cash_drawer_shift_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../../core/errors/failure.dart';
import '../../data/remote/fulus_cash_drawer_canonical_reconciler.dart';
import '../sync_handler.dart';
import '../sync_execution_lease.dart';

/// Syncs both lifecycle operations for a cash drawer shift through the
/// canonical Fulus Cloud transport.
class CashDrawerShiftSyncHandler implements SyncHandler {
  CashDrawerShiftSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required SyncExecutionLease executionLease,
    required CashDrawerShiftRepository cashDrawerShiftRepository,
    required LocationRepository locationRepository,
  })  : _db = db,
        _executionLease = executionLease,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _cashDrawerShiftRepository = cashDrawerShiftRepository,
        _locationRepository = locationRepository;
  final SyncExecutionLease _executionLease;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final CashDrawerShiftRepository _cashDrawerShiftRepository;
  final LocationRepository _locationRepository;

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
    final location = await _locationRepository.getLocationById(shift.locationId);
    if (location == null || location.serverId?.isNotEmpty != true) {
      throw StateError(
        'Cash drawer cannot sync because location ${shift.locationId} has not synced yet.',
      );
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for cash drawer sync.');
    }

    late final Map<String, dynamic> result;
    try {
      result = await _fulusSyncApi.submitOperation(
        businessId: businessId,
      operationType: 'cash_drawer_shift.create',
      operationId: item.id,
      clientReference: shift.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': shift.localId,
        'location_id': location.serverId,
        'opening_cash': shift.openingCash,
        'opened_at': shift.openedAt.toIso8601String(),
        },
      );
    } on BusinessRuleFailure {
      await _cashDrawerShiftRepository.markAttentionNeeded(shift.localId);
      rethrow;
    }

    await _markSyncedFromResult(shift.localId, item, result);
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

    late final Map<String, dynamic> result;
    try {
      result = await _fulusSyncApi.submitOperation(
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
        if (item.baseCursor != null) 'base_cursor': item.baseCursor,
        },
      );
    } on BusinessRuleFailure {
      try {
        final canonical = await _fulusSyncApi.fetchCanonicalEntity(
          businessId: businessId,
          entityType: 'cash_drawer_shift',
          entityId: serverId,
          deviceClientId: device!.deviceClientId,
        );
        await _executionLease.runProtectedTransaction(
          _db,
          () async {
            if (await _executionLease.hasNewerQueueMutation(
              entityType: 'cash_drawer_shift',
              entityLocalId: shift.localId,
              operationId: item.id,
              enqueuedAt: item.enqueuedAt,
            )) return;
            await FulusCashDrawerCanonicalReconciler(repository: _cashDrawerShiftRepository).apply(canonical);
          },
        );
      } catch (_) {
        // Preserve the original rejection; a later pull can reconcile it.
      }
      rethrow;
    }

    await _markSyncedFromResult(shift.localId, item, result);
  }

  Future<void> _markSyncedFromResult(
    String localId,
    SyncQueueItem item,
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
    operationId: item.id,
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
