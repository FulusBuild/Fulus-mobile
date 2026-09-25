import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/expense.dart';
import '../../domain/repositories/audit_repository.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'expense_mapper.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required AuditRepository auditRepository,
  })  : _db = db,
        _syncQueue = syncQueue,
        _auditRepository = auditRepository;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final AuditRepository _auditRepository;

  @override
  Future<Expense> recordExpense(ExpenseDraft draft) async {
    final localId = Ulid().toString();
    final expense = draft.toExpenseEntity(localId: localId);

    await _db.transaction(() async {
      await _db.into(_db.expenses).insert(expense.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.createExpense(localId));
    });

    return expense;
  }

  @override
  Stream<List<Expense>> watchExpenses(String locationId) {
    final query = _db.select(_db.expenses)
      ..where((e) => e.deletedAt.isNull())
      ..where((e) => e.locationId.equals(locationId))
      ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Expense?> getExpenseById(String localId) async {
    final row = await (_db.select(_db.expenses)
          ..where((e) => e.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<Expense> updateExpense({
    required String localId,
    required String description,
    required double amount,
    String? categoryId,
    required DateTime expenseDate,
    String? paymentMethod,
    String? userId,
  }) async {
    final before = await getExpenseById(localId);
    if (before == null) {
      throw ArgumentError.value(localId, 'localId', 'no such expense');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description', 'is required');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }

    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId))).write(
        ExpensesCompanion(
          description: Value(description),
          amount: Value(amount),
          categoryId: Value(categoryId),
          expenseDate: Value(expenseDate),
          paymentMethod: Value(paymentMethod),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateExpense(localId));
    });

    await _auditRepository.log(
      userId: userId,
      action: 'expense.updated',
      module: 'expenses',
      recordId: localId,
      details: {
        'before': {
          'description': before.description,
          'amount': before.amount,
          'category_id': before.categoryId,
          'expense_date': before.expenseDate.toIso8601String(),
        },
        'after': {
          'description': description,
          'amount': amount,
          'category_id': categoryId,
          'expense_date': expenseDate.toIso8601String(),
        },
      },
    );

    return (await getExpenseById(localId))!;
  }

  @override
  Future<List<Expense>> getExpensesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  }) async {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    final rows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(locationId) &
                e.deletedAt.isNull() &
                e.expenseDate.isBiggerOrEqualValue(startOfDay) &
                e.expenseDate.isSmallerThanValue(endExclusive),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? operationId,
  }) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (current == null) {
          // A missing operation row means this completion is stale. Never
          // allow an old network response to settle a mutation whose queue
          // identity is no longer present.
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'expense',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId))).write(
        ExpensesCompanion(
          serverId: Value(serverId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> markAttentionNeeded(String localId) async {
    await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId))).write(
      ExpensesCompanion(
        syncStatus: const Value(SyncStatus.attentionNeeded),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> updateReceiptPhoto({
    required String localId,
    required String? photoPath,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId))).write(
        ExpensesCompanion(
          receiptPhotoPath: Value(photoPath),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateExpense(localId));
    });
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String locationServerId,
    String? categoryId,
    required String description,
    required double amount,
    required DateTime expenseDate,
    String? paymentMethod,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    await _db.transaction(() async {
      final location = await (_db.select(_db.locations)
            ..where((l) => l.serverId.equals(locationServerId)))
          .getSingleOrNull();
      if (location == null) {
        throw StateError(
          'Canonical expense $serverId references unknown location $locationServerId.',
        );
      }

      final existing = await (_db.select(_db.expenses)
            ..where((e) => e.serverId.equals(serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();

      if (existing == null) {
        await _db.into(_db.expenses).insert(
              ExpensesCompanion.insert(
                localId: localId,
                serverId: Value(serverId),
                locationId: location.localId,
                categoryId: Value(categoryId),
                description: description,
                amount: amount,
                expenseDate: expenseDate,
                paymentMethod: Value(paymentMethod),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.expenses)..where((e) => e.localId.equals(localId))).write(
          ExpensesCompanion(
            serverId: Value(serverId),
            locationId: Value(location.localId),
            categoryId: Value(categoryId),
            description: Value(description),
            amount: Value(amount),
            expenseDate: Value(expenseDate),
            paymentMethod: Value(paymentMethod),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.expenses)
          ..where((e) => e.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;

    final now = DateTime.now();
    await (_db.update(_db.expenses)..where((e) => e.localId.equals(row.localId))).write(
      ExpensesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
