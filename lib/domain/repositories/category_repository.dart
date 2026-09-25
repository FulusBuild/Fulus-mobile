import '../entities/category.dart';

/// Same shape as CustomerRepository — see that interface's own doc
/// comment for the general reasoning (local-write-first, enqueue,
/// never await the network).
abstract class CategoryRepository {
  Future<Category> createCategory(CategoryDraft draft);

  Stream<List<Category>> watchCategories();

  Future<Category?> getCategoryById(String localId);

  Future<void> updateCategory({required String localId, String? name, String? description});

  Future<void> archiveCategory(String localId);

  /// Applies a canonical server snapshot without enqueueing an outbound
  /// sync task. Server identity is matched before allocating a new local
  /// identity, so a change received after a local create cannot duplicate
  /// the row on this device.
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? description,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies a canonical delete without enqueueing an outbound task.
  Future<void> reconcileDeleted(String serverId);

  Future<void> markSynced({required String localId, required String serverId, String? operationId});
}
