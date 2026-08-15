import 'package:json_annotation/json_annotation.dart';

part 'expense.g.dart';

/// Mirrors the Expenses table exactly. locationId is REQUIRED —
/// CORRECTED: this file previously made it optional, reasoning that
/// since backend/app/models/finance.py's Expense had no location_id
/// column, the local field should be optional too. Architecture Section
/// 7a's own table settles this directly: "`ExpenseCategory`, `Expense`,
/// `Income` — Yes — confirmed, not inferred... `location_id` is
/// required, not nullable... No hedge toward a nullable 'business-wide
/// expense' case was built in here." Treating "backend doesn't have
/// this column" as if it implied "mobile field should be optional,"
/// without actually reading what Section 7a says, was the mistake.
///
/// As of migration 0018_expense_location the backend gap itself is
/// closed too — location_id is now sent on create (see toCreateDto
/// below), not just carried locally. It briefly was required locally
/// but still withheld from the wire after that migration landed, which
/// meant every expense creation from mobile failed outright; that gap
/// is what toCreateDto's own comment documents.
class Expense {
  const Expense({
    required this.localId,
    this.serverId,
    required this.locationId,
    this.categoryId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
    this.receiptPhotoPath,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String locationId;
  final String? categoryId;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethod;

  /// **New (gap-closure pass — Receipt photo attachment on
  /// expenses).** A local file path, this device's own, never sent to
  /// the backend — see `Expenses.receiptPhotoPath`'s own doc comment
  /// in tables.dart for why (same device-local-only status as
  /// `Product.photoPath`/`Customer.photoPath`). Not part of
  /// [toCreateDto] below for that same reason.
  final String? receiptPhotoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The wire-format request, using [clientReference] (in practice
  /// always this same Expense's own localId — see
  /// ExpenseSyncHandler's call site). Sends locationId as of migration
  /// 0018_expense_location — CORRECTED: this method previously omitted
  /// it, on the (accurate when written, stale the moment that backend
  /// migration landed) claim that ExpenseCreate had no such field.
  /// Nothing here was updated when the backend gained it, which meant
  /// every expense creation from mobile would get a 422 the moment that
  /// migration shipped.
  ExpenseCreateDto toCreateDto({required String clientReference}) {
    return ExpenseCreateDto(
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      categoryId: categoryId,
      locationId: locationId,
      paymentMethod: paymentMethod,
      clientReference: clientReference,
    );
  }
}

/// POST /api/finance/expenses's body — request-only, mirrors
/// ExpenseCreate exactly (backend/app/schemas/finance.py, verified
/// directly, including client_reference from migration
/// 0013_expense_client_reference, and location_id from migration
/// 0018_expense_location).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ExpenseCreateDto {
  const ExpenseCreateDto({
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.categoryId,
    required this.locationId,
    this.paymentMethod,
    this.clientReference,
  });

  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? categoryId;
  final String locationId;
  final String? paymentMethod;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$ExpenseCreateDtoToJson(this);
}

/// POST /api/finance/expenses's response — mirrors ExpenseOut exactly.
/// No locationId here either, for the same reason the request has
/// none — see ExpensesApi._toDomain for how the caller supplies it
/// instead of this DTO carrying it.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ExpenseResponseDto {
  const ExpenseResponseDto({
    required this.id,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.categoryId,
    this.paymentMethod,
  });

  final String id;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? categoryId;
  final String? paymentMethod;

  factory ExpenseResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ExpenseResponseDtoFromJson(json);
}

/// The not-yet-persisted input to ExpenseRepository.recordExpense.
/// locationId required here too — see Expense's own doc comment;
/// resolved silently at the repository boundary for a single-location
/// business, matching SaleDraft.locationId's own treatment.
class ExpenseDraft {
  const ExpenseDraft({
    required this.locationId,
    this.categoryId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
    this.receiptPhotoPath,
  });

  final String locationId;
  final String? categoryId;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethod;

  /// See [Expense.receiptPhotoPath]'s own doc comment — set here when
  /// a photo was captured before the expense was ever saved (Add
  /// Expense's own flow); attaching one to an already-saved expense
  /// instead goes through [ExpenseRepository.updateReceiptPhoto].
  final String? receiptPhotoPath;

  Expense toExpenseEntity({required String localId}) {
    final now = DateTime.now();
    return Expense(
      localId: localId,
      locationId: locationId,
      categoryId: categoryId,
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      paymentMethod: paymentMethod,
      receiptPhotoPath: receiptPhotoPath,
      createdAt: now,
      updatedAt: now,
    );
  }
}
