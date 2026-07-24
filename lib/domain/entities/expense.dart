import 'package:json_annotation/json_annotation.dart';

part 'expense.g.dart';

/// Mirrors the Expenses table exactly. locationId is OPTIONAL — a real
/// discrepancy discovered while designing the sync handler:
/// backend/app/models/finance.py's Expense has no location_id column at
/// all, verified directly, unlike Sales (where Section 7a's rule
/// genuinely does apply). Kept as a local-only organizational tag; see
/// tables.dart's own comment on the Expenses table for the full
/// reasoning.
class Expense {
  const Expense({
    required this.localId,
    this.serverId,
    this.locationId,
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
  final String? locationId;
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
  /// field at all (backend/app/schemas/finance.py); sending it would
  /// just be silently dropped by Pydantic at best.
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
/// doc comment.
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
class ExpenseDraft {
  const ExpenseDraft({
    this.locationId,
    this.categoryId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
  });

  final String? locationId;
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
