import 'package:json_annotation/json_annotation.dart';

part 'expense.g.dart';

/// Mirrors the Expenses table exactly. locationId is REQUIRED —
/// CORRECTED: this file previously made it optional, reasoning that
/// since backend/app/models/finance.py's Expense has no location_id
/// column, the local field should be optional too. Architecture Section
/// 7a's own table settles this directly: "`ExpenseCategory`, `Expense`,
/// `Income` — Yes — confirmed, not inferred... `location_id` is
/// required, not nullable... No hedge toward a nullable 'business-wide
/// expense' case was built in here." The backend gap changes what's
/// SENT (nothing — see toCreateDto below), not what's required
/// locally — the exact same split `Sale.locationId`/`SaleCreateDto`
/// already has. Treating "backend doesn't have this column" as if it
/// implied "mobile field should be optional," without actually reading
/// what Section 7a says, was the mistake.
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The wire-format request, using [clientReference] (in practice
  /// always this same Expense's own localId — see
  /// ExpenseSyncHandler's call site). Deliberately does NOT send
  /// locationId — verified directly that ExpenseCreate has no such
  /// field at all (backend/app/schemas/finance.py). Required locally,
  /// never transmitted — see Expense's own doc comment for why those
  /// are different claims.
  ExpenseCreateDto toCreateDto({required String clientReference}) {
    return ExpenseCreateDto(
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      clientReference: clientReference,
    );
  }
}

/// POST /api/finance/expenses's body — request-only, mirrors
/// ExpenseCreate exactly (backend/app/schemas/finance.py, verified
/// directly, including client_reference from migration
/// 0013_expense_client_reference). No location_id — see Expense's own
/// doc comment: required locally, never sent.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ExpenseCreateDto {
  const ExpenseCreateDto({
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.categoryId,
    this.paymentMethod,
    this.clientReference,
  });

  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? categoryId;
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
  });

  final String locationId;
  final String? categoryId;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethod;

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
      createdAt: now,
      updatedAt: now,
    );
  }
}
