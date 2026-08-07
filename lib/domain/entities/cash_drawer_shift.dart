import 'package:json_annotation/json_annotation.dart';

part 'cash_drawer_shift.g.dart';

/// The Cash Drawer & Daily Closing — see tables.dart's
/// `CashDrawerShifts` doc comment for the full backend-mirroring
/// context (`backend/app/models/pos.py::Shift`, `pos_service.
/// open_shift`/`close_shift`).
class CashDrawerShift {
  const CashDrawerShift({
    required this.localId,
    this.serverId,
    required this.cashierUserId,
    required this.locationId,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    this.closingCash,
    this.cashDifference,
    this.closingNote,
    this.closingSummaryLocked = false,
  });

  final String localId;
  final String? serverId;
  final String cashierUserId;
  final String locationId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final double? closingCash;
  final double? cashDifference;
  final String? closingNote;
  final bool closingSummaryLocked;

  bool get isOpen => closedAt == null;

  CashDrawerShift copyWith({
    DateTime? Function()? closedAt,
    double? Function()? closingCash,
    double? Function()? cashDifference,
    String? Function()? closingNote,
    bool? closingSummaryLocked,
  }) {
    return CashDrawerShift(
      localId: localId,
      serverId: serverId,
      cashierUserId: cashierUserId,
      locationId: locationId,
      openedAt: openedAt,
      closedAt: closedAt != null ? closedAt() : this.closedAt,
      openingCash: openingCash,
      closingCash: closingCash != null ? closingCash() : this.closingCash,
      cashDifference:
          cashDifference != null ? cashDifference() : this.cashDifference,
      closingNote: closingNote != null ? closingNote() : this.closingNote,
      closingSummaryLocked: closingSummaryLocked ?? this.closingSummaryLocked,
    );
  }
}

/// Backend: `ShiftOpen` — `opening_cash` (`ge=0`), `location_id`
/// (required, no nullable fallback — Architecture Section 7a: "a till
/// belongs to a location"). `cashierUserId` is resolved by the
/// repository from `AuthRepository.currentUser`, not part of this
/// draft — a caller opening a shift for themselves doesn't supply their
/// own identity, the same way nothing else in this codebase asks the
/// caller to assert who they are.
class CashDrawerShiftDraft {
  const CashDrawerShiftDraft({
    required this.openingCash,
    required this.locationId,
  });

  final double openingCash;
  final String locationId;
}

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ShiftOpenDto {
  const ShiftOpenDto({required this.openingCash, required this.locationId});

  final double openingCash;
  final String locationId;

  Map<String, dynamic> toJson() => _$ShiftOpenDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ShiftCloseDto {
  const ShiftCloseDto({required this.closingCash, this.notes});

  final double closingCash;
  final String? notes;

  Map<String, dynamic> toJson() => _$ShiftCloseDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ShiftResponseDto {
  const ShiftResponseDto({
    required this.id,
    required this.cashierId,
    required this.locationId,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    this.closingCash,
    this.cashDifference,
  });

  final String id;
  final String cashierId;
  final String locationId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final double? closingCash;
  final double? cashDifference;

  factory ShiftResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ShiftResponseDtoFromJson(json);
}
