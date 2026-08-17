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
          ..where(
            (s) =>
                s.locationId.equals(locationId) & s.closedAt.isNull(),
          ))
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
    if (draft.openingCash < 0) {
      throw ArgumentError.value(
        draft.openingCash,
        'openingCash',
        'must be ≥ 0 (backend: ShiftOpen.opening_cash, ge=0)',
      );
    }
    final currentUser = _authRepository.currentUser;
    if (currentUser == null) {
      throw StateError('Cannot open a shift with no signed-in user.');
    }

    // The "is one already open" check and the insert that opens a new
    // one have to run as a single transaction, not two separate calls —
    // otherwise a rapid double-tap on "Open Shop" can have both calls
    // see no active shift before either insert lands, opening two
    // concurrent shifts for the same location. Wrapping both in one
    // _db.transaction() forces the second call to wait for the first to
    // fully commit, so its own check runs against the row the first
    // call just wrote.
    return _db.transaction(() async {
      final existing = await getActiveShift(locationId: draft.locationId);
      if (existing != null) {
        throw StateError(
          'A shift is already open for this location — close it before '
          'opening another.',
        );
      }

      final localId = Ulid().toString();
      final shift = CashDrawerShift(
        localId: localId,
        cashierUserId: currentUser.id,
        locationId: draft.locationId,
        openedAt: DateTime.now(),
        openingCash: draft.openingCash,
      );
      await _db.into(_db.cashDrawerShifts).insert(shift.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createCashDrawerShift(localId));
      return shift;
    });
  }

  @override
  Future<ExpectedCashPreview> computeExpectedCash(String shiftLocalId) async {
    final shiftRow = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.localId.equals(shiftLocalId)))
        .getSingleOrNull();
    if (shiftRow == null) {
      throw ArgumentError.value(shiftLocalId, 'shiftLocalId', 'no such shift');
    }
    final since = shiftRow.openedAt;

    // Cash sales — a sale can carry its payment breakdown two ways (see
    // this method's own reasoning): via SalePayments rows (the DraftCart
    // → completeSale path, which any split payment and most single-
    // method sales made through Sell will have used) or, for a sale
    // created with no payment legs recorded at all, via its own
    // aggregate paymentMethod/amountPaid directly. Checked per-sale
    // rather than with one SQL query spanning both shapes, since a
    // sale genuinely uses one or the other, never a blend of both.
    // NOTE: Sales has no `status` column (see FinanceStatsRepositoryImpl for
    // the full reasoning) — filtering on deletedAt instead, matching every
    // other repository's soft-delete convention.
    final sales = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.locationId.equals(shiftRow.locationId) &
                s.deletedAt.isNull() &
                s.saleDate.isBiggerOrEqualValue(since),
          ))
        .get();

    var cashSales = 0.0;
    for (final sale in sales) {
      final payments = await (_db.select(_db.salePayments)
            ..where((p) => p.saleLocalId.equals(sale.localId)))
          .get();
      if (payments.isNotEmpty) {
        cashSales += payments
            .where((p) => p.method == 'cash' && !p.recordedAt.isBefore(since))
            .fold<double>(0.0, (sum, p) => sum + p.amount);
      } else if (sale.paymentMethod == 'cash') {
        cashSales += sale.amountPaid;
      }
    }

    final cashExpenseRows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(shiftRow.locationId) &
                e.paymentMethod.equals('cash') &
                e.expenseDate.isBiggerOrEqualValue(since),
          ))
        .get();
    final cashExpenses =
        cashExpenseRows.fold<double>(0.0, (sum, e) => sum + e.amount);

    final expectedCash = shiftRow.openingCash + cashSales - cashExpenses;
    return ExpectedCashPreview(
      openingCash: shiftRow.openingCash,
      cashSales: cashSales,
      cashExpenses: cashExpenses,
      expectedCash: expectedCash,
    );
  }

  @override
  Future<CashDrawerShift> closeShift({
    required String shiftLocalId,
    required double closingCash,
    String? notes,
  }) async {
    if (closingCash < 0) {
      throw ArgumentError.value(
        closingCash,
        'closingCash',
        'must be ≥ 0 (backend: ShiftClose.closing_cash, ge=0)',
      );
    }

    // Same reasoning as openShift above: the already-closed check and
    // the update that closes the shift need to be one transaction, or
    // two rapid close attempts could both pass the check before either
    // write lands, and the second would silently overwrite the first's
    // closing figures instead of being rejected.
    return _db.transaction(() async {
      final row = await (_db.select(_db.cashDrawerShifts)
            ..where((s) => s.localId.equals(shiftLocalId)))
          .getSingleOrNull();
      if (row == null) {
        throw ArgumentError.value(shiftLocalId, 'shiftLocalId', 'no such shift');
      }
      if (row.closedAt != null) {
        throw StateError('This shift is already closed.');
      }

      final preview = await computeExpectedCash(shiftLocalId);
      final difference = closingCash - preview.expectedCash;
      final now = DateTime.now();

      await (_db.update(_db.cashDrawerShifts)
            ..where((s) => s.localId.equals(shiftLocalId)))
          .write(
        CashDrawerShiftsCompanion(
          closedAt: Value(now),
          closingCash: Value(closingCash),
          cashDifference: Value(difference),
          closingNote: Value(notes),
          closingSummaryLocked: const Value(true),
          updatedAt: Value(now),
        ),
      );

      await _syncQueue.enqueue(SyncTask.closeCashDrawerShift(shiftLocalId));

      final updated = await (_db.select(_db.cashDrawerShifts)
            ..where((s) => s.localId.equals(shiftLocalId)))
          .getSingle();
      return updated.toDomain();
    });
  }

  @override
  Stream<List<CashDrawerShift>> watchShiftHistory({required String locationId}) {
    final query = _db.select(_db.cashDrawerShifts)
      ..where((s) => s.locationId.equals(locationId))
      ..orderBy([(s) => OrderingTerm.desc(s.openedAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
  }) async {
    await (_db.update(_db.cashDrawerShifts)
          ..where((s) => s.localId.equals(localId)))
        .write(
      CashDrawerShiftsCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
