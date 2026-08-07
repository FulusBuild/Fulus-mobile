import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_draft.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'sale_mapper.dart';

class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
    required AuthRepository authRepository,
  })  : _db = db,
        _syncQueue = syncQueue,
        _authRepository = authRepository;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final AuthRepository _authRepository;

  @override
  Future<Sale> createSale(SaleDraft draft) async {
    final localId = Ulid().toString();
    // Best-effort, not required — a sale created with nobody signed in
    // (shouldn't normally happen once a real login screen gates the
    // app, but nothing today enforces that) simply has no cashier
    // attributed, same as a sale made before this column existed. See
    // Sale.cashierUserId's own doc comment.
    final sale = draft.toSaleEntity(
      localId: localId,
      clientReference: localId,
      cashierUserId: _authRepository.currentUser?.id,
    );

    // Volume 5's Quick Sale — checked directly against
    // backend/app/schemas/sale.py's SaleItemCreate: product_id is
    // required, no default. A sale containing one of these lines
    // genuinely cannot sync as currently designed — see
    // tables.dart's SaleItems.productLocalId doc comment.
    final hasQuickSaleItem = sale.items.any((item) => item.productLocalId == null);

    // 1. Write locally FIRST, synchronously, inside one transaction —
    //    this is what makes the sale exist and be usable (cart cleared,
    //    receipt shown, Home's total updated) before any network call
    //    is attempted, per Architecture Section 4's Offline Checkout
    //    requirement.
    await _db.transaction(() async {
      await _db.into(_db.sales).insert(sale.toDriftCompanion());
      for (final item in sale.items) {
        await _db
            .into(_db.saleItems)
            .insert(item.toDriftCompanion(saleLocalId: localId));
      }
      for (final payment in draft.payments) {
        await _db
            .into(_db.salePayments)
            .insert(payment.toDriftCompanion(saleLocalId: localId));
      }
      await _decrementLocalStock(sale.items, locationId: draft.locationId);

      if (hasQuickSaleItem) {
        // Marked attentionNeeded directly, at creation — not enqueued.
        // Enqueueing a sync task for a sale that can never succeed
        // against this backend would just retry forever; attentionNeeded
        // is this schema's existing convention for "needs a human/
        // future fix," not something invented for this case.
        await (_db.update(_db.sales)..where((s) => s.localId.equals(localId)))
            .write(const SalesCompanion(syncStatus: Value(SyncStatus.attentionNeeded)));
      }
    });

    // 2. Enqueue for sync — skipped entirely for a sale that can never
    //    sync (see above). Does NOT await a network call otherwise —
    //    hands off to the sync queue and returns immediately
    //    (Architecture Section 4's single most important structural
    //    rule for this layer).
    if (!hasQuickSaleItem) {
      await _syncQueue.enqueue(SyncTask.createSale(localId));
    }

    return sale;
  }

  @override
  Stream<List<Sale>> watchSalesForToday(String locationId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = _db.select(_db.sales)
      ..where(
        (s) =>
            s.locationId.equals(locationId) &
            s.deletedAt.isNull() &
            s.saleDate.isBiggerOrEqualValue(startOfDay) &
            s.saleDate.isSmallerThanValue(endOfDay),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]);

    // asyncMap fetches each sale's items on every emission from the
    // watched `sales` query. This reacts correctly to any create/update
    // on the Sales row itself (including markSynced below), which
    // covers every way a sale changes in this app's actual write
    // patterns — sale items are only ever written together with their
    // parent sale, in the same transaction above, never edited
    // independently afterward. It would NOT react to a hypothetical
    // direct edit of a SaleItems row with no corresponding touch to its
    // parent Sales row — worth naming honestly since that's a real,
    // if currently unused, gap versus a fully composed reactive join.
    return query.watch().asyncMap((rows) async {
      final sales = <Sale>[];
      for (final row in rows) {
        final items = await (_db.select(_db.saleItems)
              ..where((i) => i.saleLocalId.equals(row.localId)))
            .get();
        sales.add(row.toDomain(items));
      }
      return sales;
    });
  }

  @override
  Future<Sale?> getSaleByLocalId(String localId) async {
    final row = await (_db.select(_db.sales)
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    if (row == null) return null;

    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleLocalId.equals(localId)))
        .get();
    return row.toDomain(items);
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    required String invoiceNumber,
  }) async {
    await (_db.update(_db.sales)..where((s) => s.localId.equals(localId)))
        .write(
      SalesCompanion(
        serverId: Value(serverId),
        invoiceNumber: Value(invoiceNumber),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mirrors the backend's stock decrement locally, scoped to this
  /// specific location's stock row (Architecture Section 7a: stock is
  /// per-location, not a single column on Product).
  ///
  /// Deliberately a plain read-then-write, not a single atomic SQL
  /// UPDATE with a conditional guard — Architecture Section 9 is
  /// explicit that the mobile client must never try to replicate the
  /// backend's own atomic conditional-UPDATE mechanism (that's what
  /// correctly resolves concurrent decrements from OTHER devices, and
  /// only the server has the live, authoritative value needed to do
  /// that). This method only needs to be correct within this single
  /// device's own transaction, against sqlite's own single-writer
  /// model — which read-then-write, inside the same _db.transaction
  /// call in createSale above, already is.
  ///
  /// syncStatus on the ProductStockLevels row is deliberately left
  /// untouched here: per Section 9, stock effects travel to the server
  /// as part of the sale's own create request, not as an independently
  /// queued/synced write of this row — this local decrement is a
  /// same-device UI mirror, not something this method should mark as
  /// pending its own separate sync.
  Future<void> _decrementLocalStock(
    List<SaleItem> items, {
    required String locationId,
  }) async {
    for (final item in items) {
      // Quick Sale line (Volume 5) — no product to decrement stock for
      // at all. New in this pass; this loop predates Quick Sale and
      // wasn't written to expect a null productLocalId.
      final productLocalId = item.productLocalId;
      if (productLocalId == null) continue;

      final stockRow = await (_db.select(_db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productLocalId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingleOrNull();

      if (stockRow == null) {
        // No stock row exists yet for this product at this location.
        // Skipping rather than fabricating one with a negative count —
        // seeding initial stock levels is real, undone work belonging
        // to Phase 2's actual inventory feature (Volume 6), not
        // something this sale-creation path should invent a value for.
        continue;
      }

      await (_db.update(_db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productLocalId) &
                  s.locationLocalId.equals(locationId),
            ))
          .write(
        ProductStockLevelsCompanion(
          currentStock: Value(stockRow.currentStock - item.quantity),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}
