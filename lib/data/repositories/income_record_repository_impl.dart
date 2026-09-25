import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/income_record.dart';
import '../../domain/repositories/income_record_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'income_mapper.dart';

class IncomeRecordRepositoryImpl implements IncomeRecordRepository {
  IncomeRecordRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  @override
  Future<IncomeRecord> recordIncome(IncomeRecordDraft draft) async {
    final localId = Ulid().toString();
    final record = draft.toIncomeRecordEntity(localId: localId);

    await _db.transaction(() async {
      await _db.into(_db.incomeRecords).insert(record.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createIncomeRecord(localId));
    });

    return record;
  }

  @override
  Stream<List<IncomeRecord>> watchIncomeRecords(String locationId) {
    final query = _db.select(_db.incomeRecords)
      ..where((i) => i.deletedAt.isNull())
      ..where((i) => i.locationId.equals(locationId))
      ..orderBy([(i) => OrderingTerm.desc(i.incomeDate)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<IncomeRecord?> getIncomeRecordById(String localId) async {
    final row = await (_db.select(_db.incomeRecords)
          ..where((i) => i.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<List<IncomeRecord>> getIncomeRecordsForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    final rows = await (_db.select(_db.incomeRecords)
          ..where(
            (i) =>
                i.locationId.equals(locationId) &
                i.deletedAt.isNull() &
                i.incomeDate.isBiggerOrEqualValue(startOfDay) &
                i.incomeDate.isSmallerThanValue(endExclusive),
          )
          ..orderBy([(i) => OrderingTerm.desc(i.incomeDate)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
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
        if (current == null) {
          // A missing operation row means this completion is stale. Never
          // allow an old network response to settle a mutation whose queue
          // identity is no longer present.
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'income_record',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.incomeRecords)..where((x) => x.localId.equals(localId))).write(
        IncomeRecordsCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> markAttentionNeeded(String localId) async {
    await (_db.update(_db.incomeRecords)..where((i) => i.localId.equals(localId))).write(
      IncomeRecordsCompanion(
        syncStatus: const Value(SyncStatus.attentionNeeded),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String locationServerId,
    required String source,
    required double amount,
    required DateTime incomeDate,
    String? notes,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    await _db.transaction(() async {
      final location = await (_db.select(_db.locations)
            ..where((l) => l.serverId.equals(locationServerId)))
          .getSingleOrNull();
      if (location == null) {
        throw StateError(
          'Canonical income $serverId references unknown location $locationServerId.',
        );
      }

      final existing = await (_db.select(_db.incomeRecords)
            ..where((i) => i.serverId.equals(serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();

      if (existing == null) {
        await _db.into(_db.incomeRecords).insert(
              IncomeRecordsCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                locationId: location.localId,
                source: source,
                amount: amount,
                incomeDate: incomeDate,
                notes: Value(notes),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.incomeRecords)..where((i) => i.localId.equals(localId))).write(
          IncomeRecordsCompanion(
            serverId: Value(serverId),
            locationId: Value(location.localId),
            source: Value(source),
            amount: Value(amount),
            incomeDate: Value(incomeDate),
            notes: Value(notes),
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
    final row = await (_db.select(_db.incomeRecords)
          ..where((i) => i.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;

    final now = DateTime.now();
    await (_db.update(_db.incomeRecords)..where((i) => i.localId.equals(row.localId))).write(
      IncomeRecordsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
