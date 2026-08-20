import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/return_request.dart';
import '../../domain/repositories/customer_credit_repository.dart';
import '../../domain/repositories/return_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../../sync/sync_queue.dart';
import 'return_mapper.dart';

class ReturnRepositoryImpl implements ReturnRepository {
  ReturnRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required CustomerCreditRepository customerCreditRepository,
  })  : _db = db,
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
  Future<
      ({
        Map<String, ({int quantity, double totalLineAmount})> purchased,
        Map<String, int> alreadyClaimed,
      })> _purchasedAndClaimed(String originalSaleLocalId) async {
    final itemRows = await (_db.select(_db.saleItems)
          ..where((i) => i.saleLocalId.equals(originalSaleLocalId)))
        .get();

    final purchased = <String, ({int quantity, double totalLineAmount})>{};
    for (final row in itemRows) {
      final productId = row.productLocalId;
      // Quick Sale lines (Volume 5) were never catalog stock — nothing
      // for a return to restore or claim against.
      if (productId == null) continue;
      final existing = purchased[productId];
      purchased[productId] = (
        quantity: (existing?.quantity ?? 0) + row.quantity,
        totalLineAmount:
            (existing?.totalLineAmount ?? 0.0) + row.quantity * row.unitPrice,
      );
    }

    final priorReturnRows = await (_db.select(_db.returnRequests)
          ..where(
            (r) =>
                r.originalSaleLocalId.equals(originalSaleLocalId) &
                r.status.equals(ReturnStatus.rejected.name).not(),
          ))
        .get();

    final alreadyClaimed = <String, int>{};
    for (final returnRow in priorReturnRows) {
      final itemRows = await (_db.select(_db.returnItems)
            ..where((i) => i.returnLocalId.equals(returnRow.localId)))
          .get();
      for (final item in itemRows) {
        alreadyClaimed[item.productLocalId] =
            (alreadyClaimed[item.productLocalId] ?? 0) + item.quantity;
      }
    }

    return (purchased: purchased, alreadyClaimed: alreadyClaimed);
  }

  /// Backend: `unit_price = info["total"] / info["qty"]` inside
  /// `create_return` — a *weighted average* across every line for this
  /// product within the sale, not a single line's price. Needed because
  /// the same product can appear more than once in a sale at different
  /// effective prices (a per-line discount on one appearance but not
  /// another, or a manually overridden `unitPrice` on one line), and a
  /// return doesn't ask which specific line a returned unit came from —
  /// this is the fairest single price to refund at across all of them.
  double _weightedAveragePrice({
    required double totalLineAmount,
    required int totalQuantity,
  }) {
    if (totalQuantity == 0) return 0.0;
    return totalLineAmount / totalQuantity;
  }

  Future<List<ReturnItem>> _itemsForReturn(String returnLocalId) async {
    final rows = await (_db.select(_db.returnItems)
          ..where((i) => i.returnLocalId.equals(returnLocalId)))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  Future<ReturnRequestRow> _requireReturnRow(String localId) async {
    final row = await (_db.select(_db.returnRequests)
          ..where((r) => r.localId.equals(localId)))
        .getSingleOrNull();
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
        purchasedQuantity: entry.value.quantity,
        alreadyReturned: claimed,
        remainingReturnable: entry.value.quantity - claimed,
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

    var refundAmount = 0.0;
    for (final requested in items) {
      if (requested.quantity <= 0) {
        throw ArgumentError.value(requested.quantity, 'quantity', 'must be > 0');
      }
      final info = data.purchased[requested.productLocalId];
      final claimed = data.alreadyClaimed[requested.productLocalId] ?? 0;

      // Backend's two rejection checks, same order: not part of the
      // sale at all, then exceeds what's still eligible.
      if (info == null || info.quantity == 0) {
        throw ArgumentError.value(
          requested.productLocalId,
          'productLocalId',
          'was not part of the original sale',
        );
      }
      final remaining = info.quantity - claimed;
      if (requested.quantity > remaining) {
        throw ArgumentError(
          'Cannot return ${requested.quantity} unit(s) of '
          '${requested.productLocalId} — only $remaining unit(s) remain '
          'eligible for return on this sale.',
        );
      }

      final unitPrice = _weightedAveragePrice(
        totalLineAmount: info.totalLineAmount,
        totalQuantity: info.quantity,
      );
      refundAmount += unitPrice * requested.quantity;
    }

    final now = DateTime.now();
    final returnLocalId = Ulid().toString();
    final returnItems = items
        .map(
          (r) => ReturnItem(
            localId: Ulid().toString(),
            returnLocalId: returnLocalId,
            productLocalId: r.productLocalId,
            quantity: r.quantity,
          ),
        )
        .toList();
    final returnRequest = ReturnRequest(
      localId: returnLocalId,
      originalSaleLocalId: originalSaleLocalId,
      status: autoApprove ? ReturnStatus.approved : ReturnStatus.pending,
      returnReason: returnReason,
      refundAmount: double.parse(refundAmount.toStringAsFixed(2)),
      refundMethod: refundMethod,
      inventoryRestored: false,
      isVoid: isVoid,
      items: returnItems,
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction(() async {
      await _db.into(_db.returnRequests).insert(returnRequest.toDriftCompanion());
      for (final item in returnItems) {
        await _db.into(_db.returnItems).insert(item.toDriftCompanion());
      }
    });

    // Same "no clientReference, a retry can create a genuine duplicate"
    // status as Categories/Suppliers — enqueued anyway, same reasoning:
    // the alternative (never syncing) is worse than a rare, honestly-
    // documented duplicate-on-retry risk.
    await _syncQueue.enqueue(SyncTask.createReturn(returnLocalId));

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
    final saleRow = await (_db.select(_db.sales)
          ..where((s) => s.localId.equals(saleLocalId)))
        .getSingleOrNull();
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

    final created = await createReturn(
      originalSaleLocalId: saleLocalId,
      items: items,
      returnReason: reason,
      // Not a new refund channel — undoes the original payment the same
      // way it was made, same as the "matches the original payment
      // method by default" convention a real refund follows.
      refundMethod: saleRow.paymentMethod ?? 'cash',
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
    if (_statusFromRow(row) != ReturnStatus.pending) {
      throw StateError('Only pending returns can be approved or rejected.');
    }

    final newStatus = approve ? ReturnStatus.approved : ReturnStatus.rejected;
    await (_db.update(_db.returnRequests)
          ..where((r) => r.localId.equals(returnLocalId)))
        .write(
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
    if (_statusFromRow(row) != ReturnStatus.approved) {
      throw StateError('This return must be approved before it can be completed.');
    }
    final sale = await (_db.select(_db.sales)
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
        final stockRow = await (_db.select(_db.productStockLevels)
              ..where(
                (s) =>
                    s.productLocalId.equals(item.productLocalId) &
                    s.locationLocalId.equals(sale.locationId),
              ))
            .getSingleOrNull();
        final currentStock = stockRow?.currentStock ?? 0;
        await _db.into(_db.productStockLevels).insertOnConflictUpdate(
              ProductStockLevelsCompanion.insert(
                productLocalId: item.productLocalId,
                locationLocalId: sale.locationId,
                currentStock: Value(currentStock + item.quantity),
                updatedAt: DateTime.now(),
                syncStatus: SyncStatus.pending,
              ),
            );
      }

      // Credit-sale balance adjustment — only when there's actually
      // something still owed on this specific sale to reduce.
      if (sale.customerId != null && sale.total > sale.amountPaid) {
        final saleBalanceDue =
            double.parse((sale.total - sale.amountPaid).toStringAsFixed(2));
        final adjustment =
            row.refundAmount < saleBalanceDue ? row.refundAmount : saleBalanceDue;
        if (adjustment > 0) {
          await _customerCreditRepository.recordRefundAdjustment(
            customerLocalId: sale.customerId!,
            amount: adjustment,
            saleLocalId: sale.localId,
          );
        }
      }

      await (_db.update(_db.returnRequests)
            ..where((r) => r.localId.equals(returnLocalId)))
          .write(
        ReturnRequestsCompanion(
          status: Value(ReturnStatus.completed.name),
          inventoryRestored: const Value(true),
          completedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final updatedRow = await _requireReturnRow(returnLocalId);
      return updatedRow.toDomain(items: items);
    });
  }

  ReturnStatus _statusFromRow(ReturnRequestRow row) {
    // Reuses the mapper's own parsing rather than re-implementing the
    // same switch here — `items: const []` is fine for a status-only
    // read; nothing here looks at the items list.
    return row.toDomain(items: const []).status;
  }

  @override
  Future<ReturnRequest?> getReturnById(String localId) async {
    final row = await (_db.select(_db.returnRequests)
          ..where((r) => r.localId.equals(localId)))
        .getSingleOrNull();
    if (row == null) return null;
    final items = await _itemsForReturn(localId);
    return row.toDomain(items: items);
  }

  @override
  Stream<List<ReturnRequest>> watchReturns({ReturnStatus? status, bool? isVoid}) {
    final query = _db.select(_db.returnRequests)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (status != null) {
      query.where((r) => r.status.equals(status.name));
    }
    if (isVoid != null) {
      query.where((r) => r.isVoid.equals(isVoid));
    }
    return query.watch().asyncMap((rows) async {
      final results = <ReturnRequest>[];
      for (final row in rows) {
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
  }) async {
    await (_db.update(_db.returnRequests)
          ..where((r) => r.localId.equals(localId)))
        .write(
      ReturnRequestsCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
