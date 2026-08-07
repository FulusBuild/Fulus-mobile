import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'category_mapper.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<Category> createCategory(CategoryDraft draft) async {
    final localId = Ulid().toString();
    final category = draft.toCategoryEntity(localId: localId);

    await _db.into(_db.categories).insert(category.toDriftCompanion());

    await _syncQueue.enqueue(SyncTask.createCategory(localId));

    return category;
  }

  @override
  Stream<List<Category>> watchCategories() {
    final query = _db.select(_db.categories)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Category?> getCategoryById(String localId) async {
    final row = await (_db.select(_db.categories)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.categories)..where((c) => c.localId.equals(localId)))
        .write(
      CategoriesCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
