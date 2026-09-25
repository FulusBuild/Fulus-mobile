import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/cash_drawer_shift.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/cash_drawer_shift_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'cash_drawer_shift_mapper.dart';

class CashDrawerShiftRepositoryImpl implements CashDrawerShiftRepository {
  CashDrawerShiftRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required AuthRepository authRepository,
  })  : _db = db,
        _syncQueue = syncQueue,
        _authRepository = authRepository;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final AuthRepository _authRepository;

  @override
  Future<CashDrawerShift?> getActiveShift({required String locationId}) async {
    final row = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.locationId.equals(locationId) & s.closedAt.isNull()))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<CashDrawerShift?> getShiftById(String localId) async {
    final row = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<CashDrawerShift> openShift(CashDrawerShiftDraft draft) async {
    if (draft.openingCash < 0) throw ArgumentError.value(draft.openingCash, 'openingCash', 'must be ≥ 0');
    final currentUser = _authRepository.currentUser;
    if (currentUser == null) throw StateError('Cannot open a shift with no signed-in user.');
    return _db.transaction(() async {
      final existing = await getActiveShift(locationId: draft.locationId);
      if (existing != null) throw StateError('A shift is already open for this location — close it before opening another.');
      final localId = Ulid().toString();
      final shift = CashDrawerShift(localId: localId, cashierUserId: currentUser.id, locationId: draft.locationId, openedAt: DateTime.now(), openingCash: draft.openingCash);
      await _db.into(_db.cashDrawerShifts).insert(shift.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createCashDrawerShift(localId));
      return shift;
    });
  }

  @override
  Future<ExpectedCashPreview> computeExpectedCash(String shiftLocalId) async {
    final shiftRow = await (_db.select(_db.cashDrawerShifts)..where((s) => s.localId.equals(shiftLocalId))).getSingleOrNull();
    if (shiftRow == null) throw ArgumentError.value(shiftLocalId, 'shiftLocalId', 'no such shift');
    final since = shiftRow.openedAt;
    final sales = await (_db.select(_db.sales)..where((s) => s.locationId.equals(shiftRow.locationId) & s.deletedAt.isNull() & s.saleDate.isBiggerOrEqualValue(since))).get();
    var cashSales = 0.0;
    for (final sale in sales) {
      final payments = await (_db.select(_db.salePayments)..where((p) => p.saleLocalId.equals(sale.localId))).get();
      if (payments.isNotEmpty) {
        cashSales += payments.where((p) => p.method == 'cash' && !p.recordedAt.isBefore(since)).fold<double>(0.0, (sum, p) => sum + p.amount);
      } else if (sale.paymentMethod == 'cash') {
        cashSales += sale.amountPaid;
      }
    }
    final cashExpenseRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.locationId.equals(shiftRow.locationId) &
              e.paymentMethod.equals('cash') &
              e.expenseDate.isBiggerOrEqualValue(since) &
              (e.syncStatus.equals(SyncStatus.settled.name) | e.syncStatus.equals(SyncStatus.pending.name) | e.syncStatus.equals(SyncStatus.syncing.name))))
        .get();
    final cashExpenses = cashExpenseRows.fold<double>(0.0, (sum, e) => sum + e.amount);
    final expectedCash = shiftRow.openingCash + cashSales - cashExpenses;
    return ExpectedCashPreview(openingCash: shiftRow.openingCash, cashSales: cashSales, cashExpenses: cashExpenses, expectedCash: expectedCash);
  }

  @override
  Future<CashDrawerShift> closeShift({required String shiftLocalId, required double closingCash, String? notes}) async {
    if (closingCash < 0) throw ArgumentError.value(closingCash, 'closingCash', 'must be ≥ 0');
    return _db.transaction(() async {
      final row = await (_db.select(_db.cashDrawerShifts)..where((s) => s.localId.equals(shiftLocalId))).getSingleOrNull();
      if (row == null) throw ArgumentError.value(shiftLocalId, 'shiftLocalId', 'no such shift');
      if (row.closedAt != null) throw StateError('This shift is already closed.');
      final preview = await computeExpectedCash(shiftLocalId);
      final now = DateTime.now();
      await (_db.update(_db.cashDrawerShifts)..where((s) => s.localId.equals(shiftLocalId))).write(CashDrawerShiftsCompanion(closedAt: Value(now), closingCash: Value(closingCash), cashDifference: Value(closingCash - preview.expectedCash), closingNote: Value(notes), closingSummaryLocked: const Value(true), updatedAt: Value(now)));
      await _syncQueue.enqueue(SyncTask.closeCashDrawerShift(shiftLocalId));
      return (await (_db.select(_db.cashDrawerShifts)..where((s) => s.localId.equals(shiftLocalId))).getSingle()).toDomain();
    });
  }

  @override
  Stream<List<CashDrawerShift>> watchShiftHistory({required String locationId}) {
    final query = _db.select(_db.cashDrawerShifts)..where((s) => s.locationId.equals(locationId))..orderBy([(s) => OrderingTerm.desc(s.openedAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
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
            entityType: 'cash_drawer_shift',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.cashDrawerShifts)..where((x) => x.localId.equals(localId))).write(
        CashDrawerShiftsCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> markAttentionNeeded(String localId) async {
    await (_db.update(_db.cashDrawerShifts)..where((s) => s.localId.equals(localId))).write(
      CashDrawerShiftsCompanion(
        syncStatus: const Value(SyncStatus.attentionNeeded),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String cashierUserId,
    required String locationServerId,
    required DateTime openedAt,
    DateTime? closedAt,
    required double openingCash,
    double? closingCash,
    double? cashDifference,
    String? closingNote,
    required bool closingSummaryLocked,
    required DateTime updatedAt,
  }) async {
    await _db.transaction(() async {
      final location = await (_db.select(_db.locations)..where((l) => l.serverId.equals(locationServerId))).getSingleOrNull();
      if (location == null) throw StateError('Canonical cash drawer shift $serverId references unknown location $locationServerId.');
      final existing = await (_db.select(_db.cashDrawerShifts)..where((s) => s.serverId.equals(serverId))).getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();
      final values = CashDrawerShiftsCompanion(serverId: Value(serverId), cashierUserId: Value(cashierUserId), locationId: Value(location.localId), openedAt: Value(openedAt), closedAt: Value(closedAt), openingCash: Value(openingCash), closingCash: Value(closingCash), cashDifference: Value(cashDifference), closingNote: Value(closingNote), closingSummaryLocked: Value(closingSummaryLocked), updatedAt: Value(updatedAt), syncStatus: const Value(SyncStatus.settled));
      if (existing == null) {
        await _db.into(_db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
          localId: localId,
          serverId: Value(serverId),
          cashierUserId: cashierUserId,
          locationId: location.localId,
          openedAt: openedAt,
          closedAt: Value(closedAt),
          openingCash: Value(openingCash),
          closingCash: Value(closingCash),
          cashDifference: Value(cashDifference),
          closingNote: Value(closingNote),
          closingSummaryLocked: Value(closingSummaryLocked),
          createdAt: openedAt,
          updatedAt: updatedAt,
          syncStatus: SyncStatus.settled,
        ));
      } else {
        await (_db.update(_db.cashDrawerShifts)..where((s) => s.localId.equals(localId))).write(values);
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.cashDrawerShifts)..where((s) => s.serverId.equals(serverId))).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.cashDrawerShifts)..where((s) => s.localId.equals(row.localId))).write(CashDrawerShiftsCompanion(deletedAt: Value(now), updatedAt: Value(now), syncStatus: const Value(SyncStatus.settled)));
  }
}
