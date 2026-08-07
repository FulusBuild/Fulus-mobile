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
    await _db.into(_db.expenseCategories).insert(category.toDriftCompanion());
    await _syncQueue.enqueue(SyncTask.createExpenseCategory(localId));
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
}
