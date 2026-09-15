import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/expense_repository.dart';
import '../sync_handler.dart';

/// Pushes expenses through the authoritative Fulus Cloud command API.
/// There is deliberately no API_BASE_URL fallback on the cloud path.
class ExpenseSyncHandler implements SyncHandler {
  ExpenseSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required ExpenseRepository expenseRepository,
  })  : _db = db,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _expenseRepository = expenseRepository;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final ExpenseRepository _expenseRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') throw StateError('ExpenseSyncHandler supports only create.');
    final expense = await _expenseRepository.getExpenseById(item.entityLocalId);
    if (expense == null) throw StateError('No local expense found for ${item.entityLocalId}.');
    if (expense.serverId?.isNotEmpty == true) return;
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for expense sync.');
    }
    final location = await (_db.select(_db.locations)..where((l) => l.localId.equals(expense.locationId))).getSingleOrNull();
    final locationId = location?.serverId;
    if (locationId == null || locationId.isEmpty) throw StateError('Expense location has no server identity yet.');
    var category = 'general';
    final categoryId = expense.categoryId;
    if (categoryId != null && categoryId.isNotEmpty) {
      final row = await (_db.select(_db.expenseCategories)..where((c) => c.localId.equals(categoryId))).getSingleOrNull();
      category = row?.name ?? category;
    }
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'expense.create',
      operationId: item.id,
      clientReference: expense.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'amount': expense.amount,
        'category': category,
        'description': expense.description,
        'location_id': locationId,
        'expense_date': expense.expenseDate.toIso8601String(),
        if (expense.paymentMethod != null) 'payment_method': expense.paymentMethod,
      },
    );
    final data = result['data'];
    if (data is! Map) throw StateError('Fulus expense sync returned no response data.');
    final serverId = (data['entity_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) throw StateError('Fulus expense sync returned no server entity ID.');
    await _expenseRepository.markSynced(localId: expense.localId, serverId: serverId);
  }
}
