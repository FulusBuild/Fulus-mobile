import 'package:drift/drift.dart';

import '../../domain/entities/expense_category.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension ExpenseCategoryToCompanion on ExpenseCategory {
  ExpenseCategoriesCompanion toDriftCompanion() {
    return ExpenseCategoriesCompanion.insert(
      localId: localId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      deletedAt: const Value(null),
    );
  }

  /// No `clientReference` — see `ExpenseCategoryCreateDto`'s doc
  /// comment for the confirmed backend gap.
  ExpenseCategoryCreateDto toCreateDto() => ExpenseCategoryCreateDto(name: name);
}

extension ExpenseCategoryRowToDomain on ExpenseCategoryRow {
  ExpenseCategory toDomain() {
    return ExpenseCategory(
      localId: localId,
      serverId: serverId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
