import '../entities/category.dart';

/// Same shape as CustomerRepository — see that interface's own doc
/// comment for the general reasoning (local-write-first, enqueue,
/// never await the network).
abstract class CategoryRepository {
  Future<Category> createCategory(CategoryDraft draft);

  /// Reactive — the category picker in Stock/Sell (Volume 6: "the same
  /// ones that appear as chips in Sell") needs this to update the moment
  /// a new category is created locally or a synced change arrives.
  Stream<List<Category>> watchCategories();

  Future<Category?> getCategoryById(String localId);

  Future<void> updateCategory({required String localId, String? name, String? description});

  Future<void> archiveCategory(String localId);

  Future<void> markSynced({required String localId, required String serverId});
}
