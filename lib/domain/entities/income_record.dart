import 'package:json_annotation/json_annotation.dart';

part 'income_record.g.dart';

/// Mirrors the IncomeRecords table exactly — miscellaneous income
/// outside of sales. locationId is OPTIONAL, NOT required: this file
/// previously claimed "Architecture Section 7a: locationId required,
/// same as Expenses and Sales" — verified directly against
/// backend/app/schemas/finance.py's IncomeCreate (re-confirmed against
/// the current backend, not just the earlier snapshot) and it has no
/// location_id field at all, the exact same gap Expense has (see
/// expense.dart's own doc comment for the full reasoning this mirrors).
/// tables.dart's IncomeRecords table already had this right
/// (locationId nullable) — this entity was the one file in the pair
/// still carrying the stale, wrong assumption; fixed here to match.
class IncomeRecord {
  const IncomeRecord({
    required this.localId,
    this.serverId,
    this.locationId,
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
  final String? locationId;
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
  /// 0014_income_client_reference, verified directly — this backend
  /// snapshot has it; an earlier snapshot checked during this same
  /// session did not, which is worth knowing if this is ever pointed at
  /// an older deployment). Deliberately does NOT send locationId, for
  /// the same reason as Expense: IncomeCreate has no such field, and
  /// sending it would just be silently dropped by Pydantic at best.
  /// Lives here, not on IncomeRecordDraft, for the same reason as
  /// Customer/Expense's identical placement — it needs to be callable
  /// at SYNC time, once only a persisted IncomeRecord exists.
  IncomeCreateDto toCreateDto({required String clientReference}) {
    return IncomeCreateDto(
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      notes: notes,
      clientReference: clientReference,
    );
  }
}

/// POST /api/finance/income's body — request-only, mirrors IncomeCreate
/// exactly (backend/app/schemas/finance.py, verified directly). No
/// location_id — see IncomeRecord's own doc comment.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class IncomeCreateDto {
  const IncomeCreateDto({
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
    this.clientReference,
  });

  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$IncomeCreateDtoToJson(this);
}

/// POST /api/finance/income's response — mirrors IncomeOut exactly.
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
/// locationId optional here too — see IncomeRecord's own doc comment;
/// kept purely as a local organizational tag exactly like
/// ExpenseDraft.locationId.
class IncomeRecordDraft {
  const IncomeRecordDraft({
    this.locationId,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
  });

  final String? locationId;
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
