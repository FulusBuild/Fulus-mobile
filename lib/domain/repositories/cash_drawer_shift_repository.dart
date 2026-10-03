import '../entities/cash_drawer_shift.dart';
import '../../core/money/money.dart';

class ExpectedCashPreview {
  const ExpectedCashPreview({
    required this.openingCash,
    required this.cashSales,
    required this.cashExpenses,
    required this.expectedCash,
  });

  final Money openingCash;
  final Money cashSales;
  final Money cashExpenses;
  final Money expectedCash;
}

abstract class CashDrawerShiftRepository {
  Future<CashDrawerShift?> getActiveShift({required String locationId});

  Future<CashDrawerShift?> getShiftById(String localId);

  Future<CashDrawerShift> openShift(CashDrawerShiftDraft draft);

  Future<ExpectedCashPreview> computeExpectedCash(String shiftLocalId);

  Future<CashDrawerShift> closeShift({
    required String shiftLocalId,
    required Money closingCash,
    String? notes,
  });

  Stream<List<CashDrawerShift>> watchShiftHistory({required String locationId});

  Future<void> markSynced({required String localId, required String serverId, String? operationId});

  /// Parks a permanently rejected local shift without deleting it.
  Future<void> markAttentionNeeded(String localId, {String? operationId});

  /// Applies server-authoritative shift state without creating an outbound
  /// sync task. The server location ID is resolved to the local location row.
  Future<void> reconcileServerState({
    required String serverId,
    required String cashierUserId,
    required String locationServerId,
    required DateTime openedAt,
    DateTime? closedAt,
    required Money openingCash,
    Money? closingCash,
    Money? cashDifference,
    String? closingNote,
    required bool closingSummaryLocked,
    required DateTime updatedAt,
  });

  Future<void> reconcileDeleted(String serverId);
}
