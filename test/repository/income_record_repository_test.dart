import 'package:drift/drift.dart' hide isNull;
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/income_record_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/income_record.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late IncomeRecordRepositoryImpl repository;

  // IncomeRecords.locationId is a required, real FK reference to
  // Locations (Architecture Section 7a — confirmed, not inferred, see
  // income_record.dart's own doc comment) — PRAGMA foreign_keys = ON
  // applies to test databases the same as the real one, so a row must
  // actually exist here before any IncomeRecord can be inserted at all.
  const locationId = 'loc-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = IncomeRecordRepositoryImpl(db: db, syncQueue: syncQueue);

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

  group('recordIncome', () {
    test('writes the income record locally with its location', () async {
      final result = await repository.recordIncome(
        IncomeRecordDraft(
          locationId: locationId,
          source: 'Equipment rental',
          amount: 15000,
          incomeDate: DateTime(2026, 7, 1),
        ),
      );

      expect(result.source, 'Equipment rental');
      expect(result.locationId, locationId);

      final rows = await db.select(db.incomeRecords).get();
      expect(rows, hasLength(1));
      expect(rows.single.source, 'Equipment rental');
      expect(rows.single.locationId, locationId);
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.recordIncome(
        IncomeRecordDraft(
          locationId: locationId,
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
    test('emits only income records for the given location', () async {
      await repository.recordIncome(
        IncomeRecordDraft(locationId: locationId, source: 'A', amount: 100, incomeDate: DateTime(2026, 7, 1)),
      );

      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-2',
            name: 'Other Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      await repository.recordIncome(
        IncomeRecordDraft(locationId: 'loc-2', source: 'B', amount: 200, incomeDate: DateTime(2026, 7, 2)),
      );

      final emitted = await repository.watchIncomeRecords(locationId).first;

      expect(emitted, hasLength(1));
      expect(emitted.single.source, 'A');
    });
  });

  group('getIncomeRecordById', () {
    test('returns the matching income record', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(locationId: locationId, source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
      );

      final fetched = await repository.getIncomeRecordById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getIncomeRecordById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('getIncomeRecordsForPeriod', () {
    test('includes records on both ends of the range, inclusive', () async {
      await repository.recordIncome(IncomeRecordDraft(
        locationId: locationId,
        source: 'Start-of-range',
        amount: 100,
        incomeDate: DateTime(2026, 7, 1),
      ));
      await repository.recordIncome(IncomeRecordDraft(
        locationId: locationId,
        source: 'End-of-range',
        amount: 200,
        incomeDate: DateTime(2026, 7, 31, 23, 59),
      ));

      final results = await repository.getIncomeRecordsForPeriod(
        locationId: locationId,
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      );

      expect(results.map((i) => i.source), containsAll(['Start-of-range', 'End-of-range']));
    });

    test('excludes records outside the range or from a different location', () async {
      await repository.recordIncome(IncomeRecordDraft(
        locationId: locationId,
        source: 'Too late',
        amount: 100,
        incomeDate: DateTime(2026, 8, 1),
      ));
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-2',
            name: 'Other Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      await repository.recordIncome(IncomeRecordDraft(
        locationId: 'loc-2',
        source: 'Elsewhere',
        amount: 100,
        incomeDate: DateTime(2026, 7, 15),
      ));

      final results = await repository.getIncomeRecordsForPeriod(
        locationId: locationId,
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      );

      expect(results, isEmpty);
    });
  });

  group('markAttentionNeeded', () {
    test('does not park an old rejection when a newer mutation is queued', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(locationId: locationId, source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
      );
      await (db.delete(db.syncQueueItems)
            ..where((q) => q.entityType.equals('income_record'))
            ..where((q) => q.entityLocalId.equals(created.localId)))
          .go();

      await db.into(db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: 'old-operation',
          entityType: 'income_record',
          entityLocalId: created.localId,
          operation: 'create',
          priority: 1,
          enqueuedAt: DateTime(2026, 7, 1),
          syncAttempts: const Value(0),
        ),
      );
      await db.into(db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: 'new-operation',
          entityType: 'income_record',
          entityLocalId: created.localId,
          operation: 'create',
          priority: 1,
          enqueuedAt: DateTime(2026, 7, 2),
          syncAttempts: const Value(0),
        ),
      );

      await repository.markAttentionNeeded(created.localId, operationId: 'old-operation');

      final row = await (db.select(db.incomeRecords)..where((i) => i.localId.equals(created.localId))).getSingle();
      expect(row.syncStatus, SyncStatus.pending);
    });

    test('does not park a rejection when its operation identity is missing', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(locationId: locationId, source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
      );

      await repository.markAttentionNeeded(created.localId, operationId: 'missing-operation');

      final row = await (db.select(db.incomeRecords)..where((i) => i.localId.equals(created.localId))).getSingle();
      expect(row.syncStatus, SyncStatus.pending);
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      final created = await repository.recordIncome(
        IncomeRecordDraft(locationId: locationId, source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
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
