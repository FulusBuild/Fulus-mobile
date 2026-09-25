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

    await _db.transaction(() async {
      await _db.into(_db.categories).insert(category.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createCategory(localId));
    });

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
  Future<void> updateCategory({required String localId, String? name, String? description}) async {
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final row = await (_db.select(_db.categories)..where((c) => c.localId.equals(localId))).getSingleOrNull();
    if (row == null) throw StateError('Category $localId does not exist.');
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.localId.equals(localId))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          description: description == null ? const Value.absent() : Value(description),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateCategory(localId));
    });
  }

  @override
  Future<void> archiveCategory(String localId) async {
    final row = await (_db.select(_db.categories)..where((c) => c.localId.equals(localId))).getSingleOrNull();
    if (row == null) throw StateError('Category $localId does not exist.');
    await _db.transaction(() async {
      final now = DateTime.now();
      await (_db.update(_db.categories)..where((c) => c.localId.equals(localId))).write(
        CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateCategory(localId));
    });
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? description,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final existing = await (_db.select(_db.categories)
          ..where((c) => c.serverId.equals(serverId)))
        .getSingleOrNull();
    final localId = existing?.localId ?? Ulid().toString();

    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                name: name,
                description: Value(description),
                createdAt: updatedAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.categories)..where((c) => c.localId.equals(localId))).write(
          CategoriesCompanion(
            serverId: Value(serverId),
            name: Value(name),
            description: Value(description),
            deletedAt: Value(deletedAt),
            syncStatus: const Value(SyncStatus.settled),
            updatedAt: Value(updatedAt),
          ),
        );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.categories)
          ..where((c) => c.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.categories)..where((c) => c.localId.equals(row.localId))).write(
      CategoriesCompanion(
        deletedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? operationId,
  }) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (current != null) {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'category',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.categories)..where((x) => x.localId.equals(localId))).write(
        CategoriesCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }
}
