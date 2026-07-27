import 'package:json_annotation/json_annotation.dart';

part 'income_record.g.dart';

/// Mirrors the IncomeRecords table exactly — miscellaneous income
/// outside of sales. locationId is REQUIRED — CORRECTED, again: this
/// file previously (this same engagement) made it optional, reasoning
/// that since backend/app/schemas/finance.py's IncomeCreate had no
/// location_id field, the local field should be optional too, "the same
/// gap Expense has." That reasoning is wrong, and it was wrong for
/// Expense first — this file just copied an existing mistake rather
/// than introducing a new one. Architecture Section 7a's own table is
/// unambiguous: "`ExpenseCategory`, `Expense`, `Income` — Yes —
/// confirmed, not inferred... `location_id` is required, not nullable
/// ... No hedge toward a nullable 'business-wide expense' case was
/// built in here." "Backend doesn't have this column" and "mobile field
/// should be optional" are different claims; treating the first as if
/// it implied the second, without checking
/// what the architecture doc actually says, is the actual mistake here.
class IncomeRecord {
  const IncomeRecord({
    required this.localId,
    this.serverId,
    required this.locationId,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String locationId;
  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The wire-format request, using [clientReference] (in practice
  /// always this same IncomeRecord's own localId — see
  /// IncomeSyncHandler's call site), for the same idempotency reasoning
  /// as Sale/Customer/Expense (backend/app/models/finance.py's Income
  /// has a client_reference column as of migration
  /// 0014_income_client_reference, verified directly). Sends locationId
  /// as of migration 0019_income_location — same real bug and same fix
  /// as Expense.toCreateDto: this method previously omitted it on a
  /// claim ("IncomeCreate has no such field server-side") that was true
  /// when written and stale the moment that migration landed. Lives
  /// here, not on IncomeRecordDraft, for the same reason as
  /// Customer/Expense's identical placement — it needs to be callable
  /// at SYNC time, once only a persisted IncomeRecord exists.
  IncomeCreateDto toCreateDto({required String clientReference}) {
    return IncomeCreateDto(
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      locationId: locationId,
      notes: notes,
      clientReference: clientReference,
    );
  }
}

/// POST /api/finance/income's body — request-only, mirrors IncomeCreate
/// exactly (backend/app/schemas/finance.py, verified directly,
/// including location_id from migration 0019_income_location).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class IncomeCreateDto {
  const IncomeCreateDto({
    required this.source,
    required this.amount,
    required this.incomeDate,
    required this.locationId,
    this.notes,
    this.clientReference,
  });

  final String source;
  final double amount;
  final DateTime incomeDate;
  final String locationId;
  final String? notes;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$IncomeCreateDtoToJson(this);
}

/// POST /api/finance/income's response — mirrors IncomeOut exactly. No
/// locationId here either, for the same reason the request has none —
/// see IncomeApi._toDomain for how the caller supplies it instead of
/// this DTO carrying it.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class IncomeResponseDto {
  const IncomeResponseDto({
    required this.id,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
  });

  final String id;
  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;

  factory IncomeResponseDto.fromJson(Map<String, dynamic> json) =>
      _$IncomeResponseDtoFromJson(json);
}

/// The not-yet-persisted input to IncomeRecordRepository.recordIncome.
/// locationId required here too — see IncomeRecord's own doc comment;
/// resolved silently at the repository boundary for a single-location
/// business, exactly matching SaleDraft.locationId's own treatment
/// (Architecture Section 4's SaleRepository.createSale example).
class IncomeRecordDraft {
  const IncomeRecordDraft({
    required this.locationId,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
  });

  final String locationId;
  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;

  IncomeRecord toIncomeRecordEntity({required String localId}) {
    final now = DateTime.now();
    return IncomeRecord(
      localId: localId,
      locationId: locationId,
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }
}
