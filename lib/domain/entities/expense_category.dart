import 'package:json_annotation/json_annotation.dart';

part 'expense_category.g.dart';

/// Volume 8: "Expenses work the same way in reverse — amount, a
/// category (Rent, Utilities, Transport, Wages, Other, all editable)."
/// See tables.dart's `ExpenseCategories` doc comment for the confirmed
/// no-client_reference gap this shares with Categories/Suppliers/
/// Returns.
class ExpenseCategory {
  const ExpenseCategory({
    required this.localId,
    this.serverId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class ExpenseCategoryDraft {
  const ExpenseCategoryDraft({required this.name});

  final String name;

  ExpenseCategory toEntity({required String localId}) {
    final now = DateTime.now();
    return ExpenseCategory(
      localId: localId,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }
}

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ExpenseCategoryCreateDto {
  const ExpenseCategoryCreateDto({required this.name});

  final String name;

  Map<String, dynamic> toJson() => _$ExpenseCategoryCreateDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ExpenseCategoryResponseDto {
  const ExpenseCategoryResponseDto({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseCategoryResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ExpenseCategoryResponseDtoFromJson(json);
}
