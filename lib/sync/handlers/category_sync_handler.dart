import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/categories_api.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../sync_handler.dart';

class CategorySyncHandler implements SyncHandler {
  CategorySyncHandler({
    required CategoriesApi categoriesApi,
    required CategoryRepository categoryRepository,
  })  : _categoriesApi = categoriesApi,
        _categoryRepository = categoryRepository;

  final CategoriesApi _categoriesApi;
  final CategoryRepository _categoryRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'CategorySyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final category = await _categoryRepository.getCategoryById(item.entityLocalId);
    if (category == null) {
      throw StateError(
        'No local category found for ${item.entityLocalId} — the queue '
        'item outlived its own row.',
      );
    }

    final response = await _categoriesApi.createCategory(
      CategoryCreateDto(name: category.name, description: category.description),
    );

    await _categoryRepository.markSynced(
      localId: category.localId,
      serverId: response.serverId!,
    );
  }
}
