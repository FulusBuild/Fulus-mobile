import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'expense_mapper.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<Expense> recordExpense(ExpenseDraft draft) async {
    final localId = Ulid().toString();
    final expense = draft.toExpenseEntity(localId: localId);

    await _db.into(_db.expenses).insert(expense.toDriftCompanion());

    await _syncQueue.enqueue(SyncTask.createExpense(localId));

    return expense;
  }

  @override
  Stream<List<Expense>> watchExpenses(String locationId) {
    final query = _db.select(_db.expenses)
      ..where((e) => e.deletedAt.isNull())
      ..where((e) => e.locationId.equals(locationId))
      ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Expense?> getExpenseById(String localId) async {
    final row = await (_db.select(_db.expenses)
          ..where((e) => e.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<List<Expense>> getExpensesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    final rows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(locationId) &
                e.deletedAt.isNull() &
                e.expenseDate.isBiggerOrEqualValue(startOfDay) &
                e.expenseDate.isSmallerThanValue(endExclusive),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId)))
        .write(
      ExpensesCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
