import 'package:drift/drift.dart';

import '../../domain/entities/expense.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension ExpenseToCompanion on Expense {
  ExpensesCompanion toDriftCompanion() {
    return ExpensesCompanion.insert(
      localId: localId,
      locationId: locationId,
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      categoryId: Value(categoryId),
      paymentMethod: Value(paymentMethod),
      deletedAt: const Value(null),
    );
  }
}

extension ExpenseRowToDomain on ExpenseRow {
  Expense toDomain() {
    return Expense(
      localId: localId,
      serverId: serverId,
      locationId: locationId,
      categoryId: categoryId,
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
