import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/expense_category.dart';
import '../../domain/repositories/expense_category_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'expense_category_mapper.dart';

class ExpenseCategoryRepositoryImpl implements ExpenseCategoryRepository {
  ExpenseCategoryRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<ExpenseCategory> createExpenseCategory(ExpenseCategoryDraft draft) async {
    final localId = Ulid().toString();
    final category = draft.toEntity(localId: localId);
    await _db.transaction(() async {
      await _db.into(_db.expenseCategories).insert(category.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createExpenseCategory(localId));
    });
    return category;
  }

  @override
  Stream<List<ExpenseCategory>> watchExpenseCategories() {
    final query = _db.select(_db.expenseCategories)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<ExpenseCategory?> getExpenseCategoryById(String localId) async {
    final row = await (_db.select(_db.expenseCategories)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.expenseCategories)
          ..where((c) => c.localId.equals(localId)))
        .write(
      ExpenseCategoriesCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.expenseCategories)
            ..where((c) => c.serverId.equals(serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();
      if (existing == null) {
        await _db.into(_db.expenseCategories).insert(
          ExpenseCategoriesCompanion.insert(
            localId: localId,
            serverId: Value(serverId),
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            syncStatus: SyncStatus.settled,
          ),
        );
      } else {
        await (_db.update(_db.expenseCategories)..where((c) => c.localId.equals(localId))).write(
          ExpenseCategoriesCompanion(
            serverId: Value(serverId),
            name: Value(name),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.expenseCategories)
          ..where((c) => c.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.expenseCategories)..where((c) => c.localId.equals(row.localId))).write(
      ExpenseCategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
