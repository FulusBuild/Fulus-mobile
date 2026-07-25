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

  // Expenses.locationId is a required, real FK reference to Locations
  // (Architecture Section 7a — confirmed, not inferred, see
  // expense.dart's own doc comment) — PRAGMA foreign_keys = ON applies
  // to test databases the same as the real one, so a row must actually
  // exist here before any Expense can be inserted at all.
  const locationId = 'loc-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = ExpenseRepositoryImpl(db: db, syncQueue: syncQueue);

    await db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  group('recordExpense', () {
    test('writes the expense locally with its location', () async {
      final result = await repository.recordExpense(
        ExpenseDraft(
          locationId: locationId,
          description: 'Fuel',
          amount: 3000,
          expenseDate: DateTime(2026, 7, 1),
        ),
      );

      expect(result.description, 'Fuel');
      expect(result.locationId, locationId);

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(1));
      expect(rows.single.locationId, locationId);
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.recordExpense(
        ExpenseDraft(
          locationId: locationId,
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
    test('emits only expenses for the given location', () async {
      await repository.recordExpense(
        ExpenseDraft(locationId: locationId, description: 'A', amount: 100, expenseDate: DateTime(2026, 7, 1)),
      );

      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-2',
            name: 'Other Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      await repository.recordExpense(
        ExpenseDraft(locationId: 'loc-2', description: 'B', amount: 200, expenseDate: DateTime(2026, 7, 2)),
      );

      final emitted = await repository.watchExpenses(locationId).first;

      expect(emitted, hasLength(1));
      expect(emitted.single.description, 'A');
    });
  });

  group('getExpenseById', () {
    test('returns the matching expense', () async {
      final created = await repository.recordExpense(
        ExpenseDraft(locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
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
        ExpenseDraft(locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
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
