import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/local/database/tables.dart';
import 'package:bms_mobile/data/repositories/income_record_repository_impl.dart';
import 'package:bms_mobile/domain/entities/income_record.dart';
import 'package:bms_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late IncomeRecordRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = IncomeRecordRepositoryImpl(db: db, syncQueue: syncQueue);
  });

  tearDown(() async {
    await db.close();
  });

  group('recordIncome', () {
    test('writes the income record locally with no location required', () async {
      final result = await repository.recordIncome(
        IncomeRecordDraft(
          source: 'Equipment rental',
          amount: 15000,
          incomeDate: DateTime(2026, 7, 1),
        ),
      );

      expect(result.source, 'Equipment rental');
      expect(result.locationId, isNull);

      final rows = await db.select(db.incomeRecords).get();
      expect(rows, hasLength(1));
      expect(rows.single.source, 'Equipment rental');
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.recordIncome(
        IncomeRecordDraft(
          source: 'Equipment rental',
          amount: 15000,
          incomeDate: DateTime(2026, 7, 1),
        ),
      );

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'income_record');
      expect(queued.single.operation, 'create');
      expect(queued.single.entityLocalId, result.localId);
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });
  });

  group('watchIncomeRecords', () {
    test('emits every income record when no location filter is given', () async {
      await repository.recordIncome(
        IncomeRecordDraft(source: 'A', amount: 100, incomeDate: DateTime(2026, 7, 1)),
      );
      await repository.recordIncome(
        IncomeRecordDraft(source: 'B', amount: 200, incomeDate: DateTime(2026, 7, 2)),
      );

      final emitted = await repository.watchIncomeRecords().first;

      expect(emitted, hasLength(2));
    });

    test('filters by location when one is given', () async {
      // IncomeRecords.locationId carries a real FK reference to
      // Locations (nullable, but still enforced when non-null, since
      // PRAGMA foreign_keys = ON applies to test databases the same as
      // the real one — database.dart's beforeOpen isn't conditional on
      // which executor was passed in) — a row must actually exist here
      // before a non-null locationId can be inserted against it.
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-1',
            name: 'Main Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      await repository.recordIncome(
        IncomeRecordDraft(
          locationId: 'loc-1',
          source: 'At location 1',
          amount: 100,
          incomeDate: DateTime(2026, 7, 1),
        ),
      );
      await repository.recordIncome(
        IncomeRecordDraft(source: 'No location', amount: 200, incomeDate: DateTime(2026, 7, 2)),
      );

      final emitted = await repository.watchIncomeRecords(locationId: 'loc-1').first;

      expect(emitted, hasLength(1));
      expect(emitted.single.source, 'At location 1');
    });
  });

  group('getIncomeRecordById', () {
    test('returns the matching income record', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
      );

      final fetched = await repository.getIncomeRecordById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getIncomeRecordById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
      );

      await repository.markSynced(localId: created.localId, serverId: 'server-1');

      final row = await (db.select(db.incomeRecords)
            ..where((i) => i.localId.equals(created.localId)))
          .getSingle();
      expect(row.serverId, 'server-1');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
}
