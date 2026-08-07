import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/returns_api.dart';
import '../../data/repositories/return_mapper.dart';
import '../../domain/repositories/return_repository.dart';
import '../sync_handler.dart';

class ReturnSyncHandler implements SyncHandler {
  ReturnSyncHandler({
    required ReturnsApi returnsApi,
    required ReturnRepository returnRepository,
  })  : _returnsApi = returnsApi,
        _returnRepository = returnRepository;

  final ReturnsApi _returnsApi;
  final ReturnRepository _returnRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      // approve/reject/complete pushes aren't built in this pass — see
      // ReturnRepositoryImpl.approveOrRejectReturn's own doc comment.
      throw StateError(
        'ReturnSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final returnRequest = await _returnRepository.getReturnById(item.entityLocalId);
    if (returnRequest == null) {
      throw StateError(
        'No local return found for ${item.entityLocalId} — the queue item '
        'outlived its own row.',
      );
    }

    // Pushes the return exactly as it was created locally — including
    // its local status (pending, or already approved for an
    // owner/manager's own return via autoApprove). The backend
    // independently derives its own starting status from the
    // requester's real role (`pos_service.create_return`'s own role
    // check), which is authoritative; a mismatch there is a sign the
    // local `autoApprove` guess and the server's real role disagreed,
    // surfaced by a later reconciliation pass, not resolved here.
    final response = await _returnsApi.createReturn(returnRequest.toCreateDto());

    await _returnRepository.markSynced(
      localId: returnRequest.localId,
      serverId: response.serverId!,
    );
  }
}
