import '../entities/cash_drawer_shift.dart';

/// A local preview of what `close_shift`'s own `expected_cash =
/// opening_cash + cash_sales - cash_expenses` (verified directly
/// against `pos_service._compute_shift_totals`) would compute, using
/// this device's own local data. **Necessarily an estimate, not
/// authoritative** — any sale or expense recorded on a DIFFERENT device
/// during this shift, not yet synced down to this one, won't be
/// reflected. The server's own close-shift response (`ShiftOut.
/// cash_difference`) is the authoritative figure once the close
/// actually syncs; this exists so the cashier sees a number *before*
/// committing to close, not instead of the real one.
class ExpectedCashPreview {
  const ExpectedCashPreview({
    required this.openingCash,
    required this.cashSales,
    required this.cashExpenses,
    required this.expectedCash,
  });

  final double openingCash;
  final double cashSales;
  final double cashExpenses;
  final double expectedCash;
}

abstract class CashDrawerShiftRepository {
  /// Backend: `get_active_shift` — "so a cashier reopening the app
  /// mid-shift resumes rather than accidentally opening a second one."
  Future<CashDrawerShift?> getActiveShift({required String locationId});

  Future<CashDrawerShift?> getShiftById(String localId);

  Future<CashDrawerShift> openShift(CashDrawerShiftDraft draft);

  Future<ExpectedCashPreview> computeExpectedCash(String shiftLocalId);

  /// [closingCash] is what was actually counted. Computes
  /// `cashDifference` from [computeExpectedCash], sets
  /// `closingSummaryLocked = true` — Decision 29: "sales for that day
  /// lock from further editing" once Daily Closing completes. This
  /// repository doesn't separately enforce that lock on any other
  /// write path (nothing in Sales checks it today) — it's recorded
  /// here as the fact of the matter; enforcing it against a specific
  /// edit action is that action's own job once one exists that needs
  /// to check it, the same "record the fact, let each write path decide
  /// what it means for itself" split this codebase uses elsewhere.
  Future<CashDrawerShift> closeShift({
    required String shiftLocalId,
    required double closingCash,
    String? notes,
  });

  Stream<List<CashDrawerShift>> watchShiftHistory({required String locationId});

  Future<void> markSynced({required String localId, required String serverId});
}
