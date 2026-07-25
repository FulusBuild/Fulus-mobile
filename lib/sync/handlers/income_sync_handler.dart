import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/income_api.dart';
import '../../domain/repositories/income_record_repository.dart';
import '../sync_handler.dart';

class IncomeSyncHandler implements SyncHandler {
  IncomeSyncHandler({
    required IncomeApi incomeApi,
    required IncomeRecordRepository incomeRecordRepository,
  })  : _incomeApi = incomeApi,
        _incomeRecordRepository = incomeRecordRepository;

  final IncomeApi _incomeApi;
  final IncomeRecordRepository _incomeRecordRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      // No caller in this codebase enqueues 'update'/'delete' for
      // 'income_record' today — SyncTask.createIncomeRecord is the only
      // factory that exists. Kept as an explicit, honest failure rather
      // than silently doing nothing if this is ever somehow reached.
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

    // Unlike SaleSyncHandler, there is no product/customer-serverId gap
    // to resolve here — an IncomeRecord has no foreign keys of its own
    // into anything else that would need its own prior sync.
    final response = await _incomeApi.createIncome(
      record.toCreateDto(clientReference: record.localId),
      locationLocalId: record.locationId,
    );

    await _incomeRecordRepository.markSynced(
      localId: record.localId,
      serverId: response.serverId!,
    );
  }
}
