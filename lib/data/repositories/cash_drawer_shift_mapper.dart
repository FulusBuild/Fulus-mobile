import 'package:drift/drift.dart';

import '../../domain/entities/cash_drawer_shift.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension CashDrawerShiftToCompanion on CashDrawerShift {
  CashDrawerShiftsCompanion toDriftCompanion() {
    return CashDrawerShiftsCompanion.insert(
      localId: localId,
      cashierUserId: cashierUserId,
      locationId: locationId,
      openedAt: openedAt,
      createdAt: openedAt,
      updatedAt: openedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      closedAt: Value(closedAt),
      openingCash: Value(openingCash),
      closingCash: Value(closingCash),
      cashDifference: Value(cashDifference),
      closingNote: Value(closingNote),
      closingSummaryLocked: Value(closingSummaryLocked),
    );
  }

  ShiftOpenDto toOpenDto() =>
      ShiftOpenDto(openingCash: openingCash, locationId: locationId);

  ShiftCloseDto toCloseDto() =>
      ShiftCloseDto(closingCash: closingCash!, notes: closingNote);
}

extension CashDrawerShiftRowToDomain on CashDrawerShiftRow {
  CashDrawerShift toDomain() {
    return CashDrawerShift(
      localId: localId,
      serverId: serverId,
      cashierUserId: cashierUserId,
      locationId: locationId,
      openedAt: openedAt,
      closedAt: closedAt,
      openingCash: openingCash,
      closingCash: closingCash,
      cashDifference: cashDifference,
      closingNote: closingNote,
      closingSummaryLocked: closingSummaryLocked,
    );
  }
}
