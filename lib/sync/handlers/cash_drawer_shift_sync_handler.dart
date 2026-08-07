import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/cash_drawer_shifts_api.dart';
import '../../data/repositories/cash_drawer_shift_mapper.dart';
import '../../domain/entities/cash_drawer_shift.dart';
import '../../domain/repositories/cash_drawer_shift_repository.dart';
import '../sync_handler.dart';

/// The first handler in this codebase that genuinely needs to support
/// two operations for the same entity type — every other handler
/// (`CategorySyncHandler`, `ReturnSyncHandler`, etc.) only implements
/// 'create' and explicitly throws for anything else. A shift has a real
/// second lifecycle event (`close`) that has to reach the same server
/// row `create` already pushed, not a second, independent row.
class CashDrawerShiftSyncHandler implements SyncHandler {
  CashDrawerShiftSyncHandler({
    required CashDrawerShiftsApi cashDrawerShiftsApi,
    required CashDrawerShiftRepository cashDrawerShiftRepository,
  })  : _cashDrawerShiftsApi = cashDrawerShiftsApi,
        _cashDrawerShiftRepository = cashDrawerShiftRepository;

  final CashDrawerShiftsApi _cashDrawerShiftsApi;
  final CashDrawerShiftRepository _cashDrawerShiftRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    switch (item.operation) {
      case 'create':
        await _syncCreate(item.entityLocalId);
      case 'close':
        await _syncClose(item.entityLocalId);
      default:
        throw StateError(
          'CashDrawerShiftSyncHandler does not support operation '
          '"${item.operation}".',
        );
    }
  }

  Future<void> _syncCreate(String localId) async {
    final shift = await _requireShift(localId);
    final response = await _cashDrawerShiftsApi.openShift(shift.toOpenDto());
    await _cashDrawerShiftRepository.markSynced(
      localId: shift.localId,
      serverId: response.serverId!,
    );
  }

  Future<void> _syncClose(String localId) async {
    final shift = await _requireShift(localId);
    if (shift.serverId == null) {
      // The 'create' push for this same shift hasn't reached the server
      // yet — there's no server-side row to close. Both tasks share
      // `SyncPriority.salesAndPayments` and 'create' is always enqueued
      // strictly before 'close' can be (a shift has to exist locally
      // before it can be closed), so under normal FIFO-within-priority
      // processing this shouldn't actually happen — but if it does
      // (e.g. a retry ordering edge case), throwing lets the sync
      // engine's normal retry/backoff handle it rather than this
      // handler guessing at a resolution.
      throw StateError(
        'Cannot sync a shift close before its create has synced '
        '(no serverId yet for $localId).',
      );
    }
    final response = await _cashDrawerShiftsApi.closeShift(
      serverId: shift.serverId!,
      dto: shift.toCloseDto(),
    );
    await _cashDrawerShiftRepository.markSynced(
      localId: shift.localId,
      serverId: response.serverId!,
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
