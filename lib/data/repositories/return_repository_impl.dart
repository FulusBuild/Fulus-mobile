import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/errors/failure.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/return_request.dart';
import '../../domain/repositories/customer_credit_repository.dart';
import '../../domain/repositories/return_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../../sync/sync_queue.dart';
import 'return_mapper.dart';
import 'sale_mapper.dart';

class ReturnRepositoryImpl implements ReturnRepository {
  ReturnRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required CustomerCreditRepository customerCreditRepository,
  }) : _db = db,
       _syncQueue = syncQueue,
       _customerCreditRepository = customerCreditRepository;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final CustomerCreditRepository _customerCreditRepository;

  /// Mirrors `pos_service._purchased_and_claimed` exactly — shared by
  /// [getReturnEligibility] and [createReturn] for the same reason the
  /// backend shares it: "so the two can never drift out of sync with
  /// each other." Per product: total quantity purchased across every
  /// line of the original sale (a product can appear more than once, at
  /// different prices) and total quantity already claimed by any
  /// *non-rejected* prior return against the same sale — a rejected
  /// return frees its claimed quantity back up; pending/approved/
  /// completed ones don't.
  Future<bool> _isSaleInActiveLocation(String saleLocalId) async {
    final session = await (_db.select(
      _db.sessions,
    )..where((row) => row.id.equals('current'))).getSingleOrNull();
    if (session == null || session.activeLocationId == null) return false;
    final sale = await (_db.select(
      _db.sales,
    )..where((row) => row.localId.equals(saleLocalId))).getSingleOrNull();
    return sale != null && sale.locationId == session.activeLocationId;
  }

  Future<void> _requireSaleInActiveLocation(String saleLocalId) async {
    if (!await _isSaleInActiveLocation(saleLocalId)) {
      throw StateError(
        'Returns are restricted to sales in the active location.',
      );
    }
  }

  Future<({Map<String, int> purchased, Map<String, int> alreadyClaimed})>
  _purchasedAndClaimed(String originalSaleLocalId) async {
    await _requireSaleInActiveLocation(originalSaleLocalId);
    final itemRows = await (_db.select(
      _db.saleItems,
    )..where((i) => i.saleLocalId.equals(originalSaleLocalId))).get();

    final purchased = <String, int>{};
    for (final row in itemRows) {
      final productId = row.productLocalId;
      // Quick Sale lines (Volume 5) were never catalog stock — nothing
      // for a return to restore or claim against.
      if (productId == null) continue;
      purchased.update(
        productId,
        (quantity) => quantity + row.quantity,
        ifAbsent: () => row.quantity,
      );
    }

    final priorReturnRows =
        await (_db.select(_db.returnRequests)..where(
              (r) =>
                  r.originalSaleLocalId.equals(originalSaleLocalId) &
                  r.status.equals(ReturnStatus.rejected.name).not(),
            ))
            .get();

    final alreadyClaimed = <String, int>{};
    for (final returnRow in priorReturnRows) {
      final itemRows = await (_db.select(
        _db.returnItems,
      )..where((i) => i.returnLocalId.equals(returnRow.localId))).get();
      for (final item in itemRows) {
        alreadyClaimed[item.productLocalId] =
            (alreadyClaimed[item.productLocalId] ?? 0) + item.quantity;
      }
    }

    return (purchased: purchased, alreadyClaimed: alreadyClaimed);
  }

  Future<List<ReturnItem>> _itemsForReturn(String returnLocalId) async {
    final rows = await (_db.select(
      _db.returnItems,
    )..where((i) => i.returnLocalId.equals(returnLocalId))).get();
    return rows.map((r) => r.toDomain()).toList();
  }

  Future<ReturnRequestRow> _requireReturnRow(String localId) async {
    final row = await (_db.select(
      _db.returnRequests,
    )..where((r) => r.localId.equals(localId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(localId, 'returnLocalId', 'no such return');
    }
    return row;
  }

  @override
  Future<List<ReturnEligibilityLine>> getReturnEligibility(
    String originalSaleLocalId,
  ) async {
    final data = await _purchasedAndClaimed(originalSaleLocalId);
    return data.purchased.entries.map((entry) {
      final claimed = data.alreadyClaimed[entry.key] ?? 0;
      return ReturnEligibilityLine(
        productLocalId: entry.key,
        purchasedQuantity: entry.value,
        alreadyReturned: claimed,
        remainingReturnable: entry.value - claimed,
      );
    }).toList();
  }

  @override
  Future<ReturnRequest> createReturn({
    required String originalSaleLocalId,
    required List<ReturnItemRequest> items,
    required String returnReason,
    required String refundMethod,
    required bool autoApprove,
    bool isVoid = false,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must have at least one item');
    }
    if (returnReason.trim().isEmpty) {
      throw ArgumentError.value(
        returnReason,
        'returnReason',
        'is required (backend: Return.return_reason, min_length=1)',
      );
    }
    if (refundMethod.trim().isEmpty) {
      throw ArgumentError.value(refundMethod, 'refundMethod', 'is required');
    }

    final data = await _purchasedAndClaimed(originalSaleLocalId);

    final requestedQuantities = <String, int>{};
    for (final requested in items) {
      if (requested.quantity <= 0) {
        throw ArgumentError.value(
          requested.quantity,
          'quantity',
          'must be > 0',
        );
      }
      requestedQuantities.update(
        requested.productLocalId,
        (quantity) => quantity + requested.quantity,
        ifAbsent: () => requested.quantity,
      );
    }

    for (final requested in requestedQuantities.entries) {
      final info = data.purchased[requested.key];
      final claimed = data.alreadyClaimed[requested.key] ?? 0;

      // Backend's two rejection checks, same order: not part of the
      // sale at all, then exceeds what's still eligible.
      if (info == null || info == 0) {
        throw ArgumentError.value(
          requested.key,
          'productLocalId',
          'was not part of the original sale',
        );
      }
      final remaining = info - claimed;
      if (requested.value > remaining) {
        throw ArgumentError(
          'Cannot return ${requested.value} unit(s) of '
          '${requested.key} — only $remaining unit(s) remain '
          'eligible for return on this sale.',
        );
      }
    }

    final saleRow =
        await (_db.select(_db.sales)
              ..where((sale) => sale.localId.equals(originalSaleLocalId)))
            .getSingleOrNull();
    if (saleRow == null) throw StateError('Original sale not found.');
    final saleItems = await (_db.select(
      _db.saleItems,
    )..where((item) => item.saleLocalId.equals(originalSaleLocalId))).get();
    final sale = saleRow.toDomain(saleItems);
    final refundAmount = sale.refundAmountFor(requestedQuantities);

    if (refundMethod.trim().toLowerCase() == 'credit') {
      final customerLocalId = sale.customerId;
      if (customerLocalId == null) {
        throw const BusinessRuleFailure(
          'An account-credit refund requires a customer on the original sale.',
        );
      }
      final paymentRows = await (_db.select(
        _db.salePayments,
      )..where((payment) => payment.saleLocalId.equals(sale.localId))).get();
      final creditPayments = paymentRows
          .where((payment) => payment.method.trim().toLowerCase() == 'credit')
          .toList();
      final creditExtended = creditPayments.isNotEmpty
          ? creditPayments.fold<Money>(
              0,
              (sum, payment) => sum + payment.amount,
            )
          : ((sale.total - sale.amountPaid) > 0
                ? sale.total - sale.amountPaid
                : 0);
      final customer = await (_db.select(
        _db.customers,
      )..where((row) => row.localId.equals(customerLocalId))).getSingleOrNull();
      final outstandingBalance = customer?.outstandingBalance ?? 0;
      if (creditExtended <= 0 || outstandingBalance <= 0) {
        throw const BusinessRuleFailure(
          'Account-credit refunds require an outstanding credit sale balance.',
        );
      }
      if (refundAmount > creditExtended || refundAmount > outstandingBalance) {
        throw const BusinessRuleFailure(
          'The refund exceeds the outstanding account-credit balance.',
        );
      }
    }

    final now = DateTime.now();
    final returnLocalId = Ulid().toString();
    final returnItems = requestedQuantities.entries
        .map(
          (entry) => ReturnItem(
            localId: Ulid().toString(),
            returnLocalId: returnLocalId,
            productLocalId: entry.key,
            quantity: entry.value,
          ),
        )
        .toList();
    final returnRequest = ReturnRequest(
      localId: returnLocalId,
      originalSaleLocalId: originalSaleLocalId,
      status: autoApprove ? ReturnStatus.approved : ReturnStatus.pending,
      returnReason: returnReason,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      inventoryRestored: false,
      isVoid: isVoid,
      items: returnItems,
      createdAt: now,
      updatedAt: now,
    );

    // A return only becomes a cloud mutation when it is completed. The
    // server-side return command is authoritative and completes the return
    // atomically; syncing a still-pending local approval would make the two
    // devices disagree about whether the return exists.
    await _db.transaction(() async {
      await _db
          .into(_db.returnRequests)
          .insert(returnRequest.toDriftCompanion());
      for (final item in returnItems) {
        await _db.into(_db.returnItems).insert(item.toDriftCompanion());
      }
    });

    // Same "no clientReference, a retry can create a genuine duplicate"
    // status as Categories/Suppliers — enqueued anyway, same reasoning:
    // the alternative (never syncing) is worse than a rare, honestly-
    // documented duplicate-on-retry risk.
    return returnRequest;
  }

  @override
  Future<ReturnRequest> voidSale({
    required String saleLocalId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'is required');
    }
    final saleRow = await (_db.select(
      _db.sales,
    )..where((s) => s.localId.equals(saleLocalId))).getSingleOrNull();
    if (saleRow == null) {
      throw ArgumentError.value(saleLocalId, 'saleLocalId', 'no such sale');
    }

    final eligibility = await getReturnEligibility(saleLocalId);
    final items = eligibility
        .where((line) => line.remainingReturnable > 0)
        .map(
          (line) => ReturnItemRequest(
            productLocalId: line.productLocalId,
            quantity: line.remainingReturnable,
          ),
        )
        .toList();
    if (items.isEmpty) {
      throw StateError(
        'Nothing left on this sale to void — it may already be fully '
        'refunded or voided.',
      );
    }

    const supportedRefundMethods = {'cash', 'card', 'mobile_money', 'credit'};
    final originalMethod = saleRow.paymentMethod?.trim().toLowerCase();

    final created = await createReturn(
      originalSaleLocalId: saleLocalId,
      items: items,
      returnReason: reason,
      // Preserve the original method when the cloud return contract
      // supports it. Split and legacy methods have no direct refund
      // channel, so use cash; the server still reverses eligible credit
      // balance before calculating any cash refund.
      refundMethod:
          originalMethod != null &&
              supportedRefundMethods.contains(originalMethod)
          ? originalMethod
          : 'cash',
      autoApprove: true,
      isVoid: true,
    );
    return completeReturn(created.localId);
  }

  @override
  Future<ReturnRequest> approveOrRejectReturn({
    required String returnLocalId,
    required bool approve,
  }) async {
    final row = await _requireReturnRow(returnLocalId);
    await _requireSaleInActiveLocation(row.originalSaleLocalId);
    if (_statusFromRow(row) != ReturnStatus.pending) {
      throw StateError('Only pending returns can be approved or rejected.');
    }

    final newStatus = approve ? ReturnStatus.approved : ReturnStatus.rejected;
    await (_db.update(
      _db.returnRequests,
    )..where((r) => r.localId.equals(returnLocalId))).write(
      ReturnRequestsCompanion(
        status: Value(newStatus.name),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // **Not pushed to the server in this pass** — PATCH .../approve is
    // a real endpoint (`pos_service.approve_return`), but extending the
    // sync-handler pattern to support a second operation per entity
    // type (today every handler, including this one's own createReturn
    // task, only implements 'create') is a genuine follow-up, not
    // silently done here. Local state (and everything completeReturn
    // does below) is correct either way; this decision just doesn't
    // reach the backend yet.
    return getReturnById(returnLocalId).then((r) => r!);
  }

  @override
  Future<ReturnRequest> completeReturn(String returnLocalId) async {
    final row = await _requireReturnRow(returnLocalId);
    await _requireSaleInActiveLocation(row.originalSaleLocalId);
    final currentStatus = _statusFromRow(row);
    // Completion is deliberately idempotent. A retry after a dropped
    // response must not restore inventory or reverse customer credit twice.
    if (currentStatus == ReturnStatus.completed) {
      final existing = await getReturnById(returnLocalId);
      if (existing == null)
        throw StateError('Return not found after completion.');
      if (existing.serverId == null || existing.serverId!.isEmpty) {
        await _syncQueue.enqueue(SyncTask.createReturn(returnLocalId));
      }
      return existing;
    }
    if (currentStatus != ReturnStatus.approved) {
      throw StateError(
        'This return must be approved before it can be completed.',
      );
    }
    final sale =
        await (_db.select(_db.sales)
              ..where((s) => s.localId.equals(row.originalSaleLocalId)))
            .getSingleOrNull();
    if (sale == null) {
      throw StateError('Original sale not found for this return.');
    }
    final items = await _itemsForReturn(returnLocalId);

    return _db.transaction(() async {
      for (final item in items) {
        // Restores via the same local ProductStockLevels adjustment
        // Sales' own optimistic stock decrement uses — see
        // SaleRepositoryImpl._decrementLocalStock's own doc comment for
        // why this is a local echo, not a StockMovement write: the
        // authoritative correction happens server-side once this
        // return itself can sync (see approveOrRejectReturn's own doc
        // comment on why that push doesn't happen in this pass yet).
        final stockRow =
            await (_db.select(_db.productStockLevels)..where(
                  (s) =>
                      s.productLocalId.equals(item.productLocalId) &
                      s.locationLocalId.equals(sale.locationId),
                ))
                .getSingleOrNull();
        final currentStock = stockRow?.currentStock ?? 0;
        await _db
            .into(_db.productStockLevels)
            .insertOnConflictUpdate(
              ProductStockLevelsCompanion.insert(
                productLocalId: item.productLocalId,
                locationLocalId: sale.locationId,
                currentStock: Value(currentStock + item.quantity),
                updatedAt: DateTime.now(),
                syncStatus: SyncStatus.pending,
              ),
            );
      }

      // Credit-sale balance adjustment. For split payments, the credit
      // leg is the amount actually extended; total - amountPaid is not
      // sufficient because amountPaid intentionally excludes the credit leg.
      // Fall back to the legacy balance-due calculation for older single-method
      // sales that predate SalePayments.
      if (sale.customerId != null) {
        final paymentRows = await (_db.select(
          _db.salePayments,
        )..where((p) => p.saleLocalId.equals(sale.localId))).get();
        final creditPayments = paymentRows
            .where((p) => p.method.trim().toLowerCase() == 'credit')
            .toList();
        final creditExtended = creditPayments.isNotEmpty
            ? creditPayments.fold<Money>(0, (sum, p) => sum + p.amount)
            : ((sale.total - sale.amountPaid) > 0
                  ? sale.total - sale.amountPaid
                  : 0);
        final customer = await (_db.select(
          _db.customers,
        )..where((c) => c.localId.equals(sale.customerId!))).getSingleOrNull();
        final outstanding = customer?.outstandingBalance ?? 0;
        final adjustment = [
          row.refundAmount,
          creditExtended,
          outstanding,
        ].reduce((left, right) => left < right ? left : right);
        if (adjustment > 0) {
          await _customerCreditRepository.recordRefundAdjustment(
            customerLocalId: sale.customerId!,
            amount: adjustment,
            saleLocalId: sale.localId,
          );
        }
      }

      await (_db.update(
        _db.returnRequests,
      )..where((r) => r.localId.equals(returnLocalId))).write(
        ReturnRequestsCompanion(
          status: Value(ReturnStatus.completed.name),
          inventoryRestored: const Value(true),
          completedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final updatedRow = await _requireReturnRow(returnLocalId);
      final completed = updatedRow.toDomain(items: items);
      if (updatedRow.serverId == null || updatedRow.serverId!.isEmpty) {
        // Keep completion and its durable outbox intent in the same database
        // transaction. SyncQueue defers its network trigger until commit.
        await _syncQueue.enqueue(SyncTask.createReturn(returnLocalId));
      }
      return completed;
    });
  }

  ReturnStatus _statusFromRow(ReturnRequestRow row) {
    // Reuses the mapper's own parsing rather than re-implementing the
    // same switch here — `items: const []` is fine for a status-only
    // read; nothing here looks at the items list.
    return row.toDomain(items: const []).status;
  }

  @override
  Future<ReturnRequest?> getReturnById(
    String localId, {
    bool forSync = false,
  }) async {
    final row = await (_db.select(
      _db.returnRequests,
    )..where((r) => r.localId.equals(localId))).getSingleOrNull();
    if (row == null) return null;
    if (!forSync && !await _isSaleInActiveLocation(row.originalSaleLocalId)) {
      return null;
    }
    final items = await _itemsForReturn(localId);
    return row.toDomain(items: items);
  }

  @override
  Stream<List<ReturnRequest>> watchReturns({
    ReturnStatus? status,
    bool? isVoid,
  }) {
    final query =
        _db.select(_db.returnRequests).join([
            innerJoin(
              _db.sales,
              _db.sales.localId.equalsExp(
                _db.returnRequests.originalSaleLocalId,
              ),
            ),
            innerJoin(_db.sessions, _db.sessions.id.equals('current')),
          ])
          ..where(_db.sales.locationId.equalsExp(_db.sessions.activeLocationId))
          ..orderBy([OrderingTerm.desc(_db.returnRequests.createdAt)]);
    if (status != null) {
      query.where(
        _db.returnRequests.status.equals(
          status == ReturnStatus.reconciliationPending
              ? 'reconciliation_pending'
              : status.name,
        ),
      );
    }
    if (isVoid != null) {
      query.where(_db.returnRequests.isVoid.equals(isVoid));
    }
    return query.watch().asyncMap((rows) async {
      final results = <ReturnRequest>[];
      for (final joinedRow in rows) {
        final row = joinedRow.readTable(_db.returnRequests);
        final items = await _itemsForReturn(row.localId);
        results.add(row.toDomain(items: items));
      }
      return results;
    });
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
        final current = await (_db.select(
          _db.syncQueueItems,
        )..where((q) => q.id.equals(operationId))).getSingleOrNull();
        if (current == null) {
          // A missing operation row means this completion is stale. Never
          // allow an old network response to settle a mutation whose queue
          // identity is no longer present.
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'return',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(
        _db.returnRequests,
      )..where((x) => x.localId.equals(localId))).write(
        ReturnRequestsCompanion(
          serverId: Value(serverId),
          syncStatus: Value(
            hasNewerMutation ? SyncStatus.pending : SyncStatus.settled,
          ),
          updatedAt: hasNewerMutation
              ? const Value.absent()
              : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> markRejected({required String localId}) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.returnRequests,
      )..where((request) => request.localId.equals(localId))).getSingleOrNull();
      if (row == null) return;
      if (!{
            ReturnStatus.completed,
            ReturnStatus.reconciliationPending,
          }.contains(_statusFromRow(row)) ||
          row.serverId != null) {
        throw StateError(
          'Only an unsynced completed return can be rejected by cloud reconciliation.',
        );
      }
      await (_db.update(
        _db.returnRequests,
      )..where((request) => request.localId.equals(localId))).write(
        ReturnRequestsCompanion(
          status: Value(ReturnStatus.rejected.name),
          inventoryRestored: const Value(false),
          completedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> markReconciliationPending({required String localId}) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.returnRequests,
      )..where((request) => request.localId.equals(localId))).getSingleOrNull();
      if (row == null) return;
      if (_statusFromRow(row) != ReturnStatus.completed ||
          row.serverId != null) {
        throw StateError(
          'Only an unsynced completed return can await cloud reconciliation.',
        );
      }
      await (_db.update(
        _db.returnRequests,
      )..where((request) => request.localId.equals(localId))).write(
        ReturnRequestsCompanion(
          status: const Value('reconciliation_pending'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }
}
