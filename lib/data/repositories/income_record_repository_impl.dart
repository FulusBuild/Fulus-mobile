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

    await _db.into(_db.incomeRecords).insert(record.toDriftCompanion());

    await _syncQueue.enqueue(SyncTask.createIncomeRecord(localId));

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
  }) async {
    await (_db.update(_db.incomeRecords)..where((i) => i.localId.equals(localId)))
        .write(
      IncomeRecordsCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
