import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/local/database/tables.dart';
import 'package:bms_mobile/data/repositories/expense_repository_impl.dart';
import 'package:bms_mobile/domain/entities/expense.dart';
import 'package:bms_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late ExpenseRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = ExpenseRepositoryImpl(db: db, syncQueue: syncQueue);
  });

  tearDown(() async {
    await db.close();
  });

  group('recordExpense', () {
    test('writes the expense locally with no location required', () async {
      final result = await repository.recordExpense(
        ExpenseDraft(
          description: 'Fuel',
          amount: 3000,
          expenseDate: DateTime(2026, 7, 1),
        ),
      );

      expect(result.description, 'Fuel');
      expect(result.locationId, isNull);

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(1));
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.recordExpense(
        ExpenseDraft(
          description: 'Fuel',
          amount: 3000,
          expenseDate: DateTime(2026, 7, 1),
        ),
      );

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'expense');
      expect(queued.single.entityLocalId, result.localId);
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });
  });

  group('watchExpenses', () {
    test('emits every expense when no location filter is given', () async {
      await repository.recordExpense(
        ExpenseDraft(description: 'A', amount: 100, expenseDate: DateTime(2026, 7, 1)),
      );
      await repository.recordExpense(
        ExpenseDraft(description: 'B', amount: 200, expenseDate: DateTime(2026, 7, 2)),
      );

      final emitted = await repository.watchExpenses().first;

      expect(emitted, hasLength(2));
    });
  });

  group('getExpenseById', () {
    test('returns the matching expense', () async {
      final created = await repository.recordExpense(
        ExpenseDraft(description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
      );

      final fetched = await repository.getExpenseById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getExpenseById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      final created = await repository.recordExpense(
        ExpenseDraft(description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
      );

      await repository.markSynced(localId: created.localId, serverId: 'server-1');

      final row = await (db.select(db.expenses)
            ..where((e) => e.localId.equals(created.localId)))
          .getSingle();
      expect(row.serverId, 'server-1');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
}
