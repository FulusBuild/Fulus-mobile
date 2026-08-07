import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/expense_categories_api.dart';
import '../../domain/repositories/expense_category_repository.dart';
import '../sync_handler.dart';

class ExpenseCategorySyncHandler implements SyncHandler {
  ExpenseCategorySyncHandler({
    required ExpenseCategoriesApi expenseCategoriesApi,
    required ExpenseCategoryRepository expenseCategoryRepository,
  })  : _expenseCategoriesApi = expenseCategoriesApi,
        _expenseCategoryRepository = expenseCategoryRepository;

  final ExpenseCategoriesApi _expenseCategoriesApi;
  final ExpenseCategoryRepository _expenseCategoryRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'ExpenseCategorySyncHandler does not support operation '
        '"${item.operation}" yet — only "create" is implemented.',
      );
    }

    final category =
        await _expenseCategoryRepository.getExpenseCategoryById(item.entityLocalId);
    if (category == null) {
      throw StateError(
        'No local expense category found for ${item.entityLocalId} — the '
        'queue item outlived its own row.',
      );
    }

    final response =
        await _expenseCategoriesApi.createExpenseCategory(category.toCreateDto());

    await _expenseCategoryRepository.markSynced(
      localId: category.localId,
      serverId: response.serverId!,
    );
  }
}
