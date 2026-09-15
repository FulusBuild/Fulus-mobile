import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/expense_category_repository.dart';
import '../sync_handler.dart';

class ExpenseCategorySyncHandler implements SyncHandler {
  ExpenseCategorySyncHandler({
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required ExpenseCategoryRepository expenseCategoryRepository,
  })  : _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _expenseCategoryRepository = expenseCategoryRepository;

  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final ExpenseCategoryRepository _expenseCategoryRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'ExpenseCategorySyncHandler does not support operation '
        '"${item.operation}" yet — only "create" is implemented.',
      );
    }

    final category = await _expenseCategoryRepository
        .getExpenseCategoryById(item.entityLocalId);
    if (category == null) {
      throw StateError(
        'No local expense category found for ${item.entityLocalId} — the '
        'queue item outlived its own row.',
      );
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError(
        'Fulus Cloud device authorization is required for expense category sync.',
      );
    }

    final response = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'expense_category.create',
      operationId: category.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'name': category.name,
      },
    );

    final data = response['data'];
    if (data is! Map || data['entity_id'] is! String) {
      throw const FormatException(
        'Fulus Cloud returned an invalid expense category response.',
      );
    }

    await _expenseCategoryRepository.markSynced(
      localId: category.localId,
      serverId: data['entity_id'] as String,
    );
  }
}
