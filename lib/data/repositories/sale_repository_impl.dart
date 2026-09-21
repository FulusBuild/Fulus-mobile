import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/diagnostics/diagnostic_logger.dart';
import '../../core/diagnostics/models/diagnostic_enums.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_draft.dart';
import '../../domain/entities/sale_payment.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/customer_credit_repository.dart';
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
    required CustomerCreditRepository customerCreditRepository,
    DiagnosticLogger? diagnosticLogger,
  })  : _db = db,
        _syncQueue = syncQueue,
        _authRepository = authRepository,
        _customerCreditRepository = customerCreditRepository,
        _diagnosticLogger = diagnosticLogger;

  final AppDatabase _db;
  final SyncQueue _syncQueue;
  final AuthRepository _authRepository;

  /// Optional, same reasoning as SyncEngine's own `_diagnosticLogger`
  /// field (see that class's doc comment) — every existing call site
  /// and test that constructs a SaleRepositoryImpl without this
  /// parameter is unaffected. Used here only for breadcrumbs
  /// (`logger?.breadcrumb(...)`, a silent no-op when null) — this class
  /// intentionally does NOT call `captureError` itself; the multi-step
  /// "Complete Sale" operation this method is one piece of is tracked
  /// one layer up, in DraftCartRepositoryImpl.completeSale, which is
  /// what actually calls `createSale` and is where a failure here is
  /// caught and reported. See DiagnosticOperation's own header comment
  /// in diagnostic_logger.dart for exactly why breadcrumbs recorded here
  /// still end up on whichever event that outer layer eventually
  /// captures.
  final DiagnosticLogger? _diagnosticLogger;

  /// Bug fix (business-logic audit): `createSale` used to persist a
  /// credit sale's own `Sale.balanceDue`/`paymentStatus` correctly
  /// (both are computed getters off `total`/`amountPaid`, and those
  /// were always right) but never told `CustomerCreditRepository`
  /// about it — `Customer.outstandingBalance` (the field every ledger/
  /// repayment/credit-limit screen in Money actually reads) simply
  /// never moved. `recordCreditSale` was fully implemented, tested in
  /// isolation, and had a doc comment elsewhere claiming it was "called
  /// by Sales" — it never was. See `_recordCreditSaleIfNeeded` below.
  final CustomerCreditRepository _customerCreditRepository;

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
    _diagnosticLogger?.breadcrumb(
      'Sale transaction started',
      category: DiagnosticCategory.sales,
      data: {'Sale ID': localId},
    );
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
      _diagnosticLogger?.breadcrumb('Inventory update started', category: DiagnosticCategory.inventory);
      await _decrementLocalStock(sale.items, locationId: draft.locationId);
      _diagnosticLogger?.breadcrumb('Inventory update completed', category: DiagnosticCategory.inventory);
      await _recordCreditSaleIfNeeded(sale, draft.payments);

      if (hasQuickSaleItem) {
        // Marked attentionNeeded directly, at creation — not enqueued.
        // Enqueueing a sync task for a sale that can never succeed
        // against this backend would just retry forever; attentionNeeded
        // is this schema's existing convention for "needs a human/
        // future fix," not something invented for this case.
        await (_db.update(_db.sales)..where((s) => s.localId.equals(localId)))
            .write(const SalesCompanion(syncStatus: Value(SyncStatus.attentionNeeded)));
      } else {
        // The business rows and their durable outbox entry must commit as one
        // local transaction. SyncQueue defers its trigger until after commit.
        await _syncQueue.enqueue(SyncTask.createSale(localId));
      }
    });
    _diagnosticLogger?.breadcrumb(
      'Sale transaction committed',
      category: DiagnosticCategory.sales,
      data: {'Sale ID': localId},
    );

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

  /// Extends the customer's `outstandingBalance` by whatever was
  /// actually extended on credit.
  ///
  /// Bug fix (business-logic audit, round 2): the previous version of
  /// this method used `sale.balanceDue` (`total - amountPaid`)
  /// exclusively — correct for a simple, single-method credit sale, but
  /// wrong the moment a *split* payment includes a `'credit'` leg
  /// alongside others: "Credit ₦50,000 + Mobile Money ₦197,250" against
  /// a ₦247,250 total makes `amountPaid == total`, so `balanceDue` is
  /// exactly 0 — even though ₦50,000 of that was never actually
  /// collected, only promised. `Customer.outstandingBalance` silently
  /// never moved for any split sale with a credit leg, no matter how
  /// large.
  ///
  /// [payments] is `draft.payments` — when it's non-empty, it's the
  /// ground truth for how this sale was actually paid, so credit
  /// extended is the sum of its `'credit'`-method legs specifically,
  /// not a value derived from the sale's overall total-vs-paid. Falls
  /// back to `balanceDue` only when `payments` is empty — the older,
  /// still-supported single-method path (`SalePayment`'s own doc
  /// comment: "a single-method sale... doesn't need this populated"),
  /// where `balanceDue` remains the correct (and only) source.
  Future<void> _recordCreditSaleIfNeeded(Sale sale, List<SalePayment> payments) async {
    final customerId = sale.customerId;
    if (customerId == null) return;

    final creditAmount = payments.isNotEmpty
        ? payments.where((p) => p.method == 'credit').fold(0.0, (sum, p) => sum + p.amount)
        : sale.balanceDue;

    if (creditAmount <= 0) return;
    await _customerCreditRepository.recordCreditSale(
      customerLocalId: customerId,
      amount: creditAmount,
      saleLocalId: sale.localId,
    );
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
  Future<List<Sale>> getSalesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
    String? cashierUserId,
  }) async {
    // Both ends treated as full calendar days, matching
    // ReportsRepositoryImpl.getSalesReport's own end-of-day handling for
    // the same "a ReportPeriod's `end` is a date, not a timestamp"
    // reason — a caller passing today's date as `end` should get
    // today's sales included, not excluded by a bare midnight cutoff.
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    final query = _db.select(_db.sales)
      ..where(
        (s) =>
            s.locationId.equals(locationId) &
            s.deletedAt.isNull() &
            s.saleDate.isBiggerOrEqualValue(startOfDay) &
            s.saleDate.isSmallerThanValue(endExclusive),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]);
    // Employee data isolation — see this parameter's own doc comment on
    // the interface.
    if (cashierUserId != null) {
      query.where((s) => s.cashierUserId.equals(cashierUserId));
    }
    final rows = await query.get();

    final sales = <Sale>[];
    for (final row in rows) {
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleLocalId.equals(row.localId)))
          .get();
      sales.add(row.toDomain(items));
    }
    return sales;
  }

  @override
  Future<List<Sale>> getSalesForCustomer({
    required String customerId,
    String? cashierUserId,
  }) async {
    // Deliberately no locationId filter — see this method's own doc
    // comment on the interface: a customer's purchase history is
    // business-wide, same as Customer itself.
    final query = _db.select(_db.sales)
      ..where((s) => s.customerId.equals(customerId) & s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]);
    // Employee data isolation — see this parameter's own doc comment on
    // the interface.
    if (cashierUserId != null) {
      query.where((s) => s.cashierUserId.equals(cashierUserId));
    }
    final rows = await query.get();

    final sales = <Sale>[];
    for (final row in rows) {
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleLocalId.equals(row.localId)))
          .get();
      sales.add(row.toDomain(items));
    }
    return sales;
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
        throw StateError(
          'No stock record exists for product $productLocalId at location $locationId.',
        );
      }

      final newStock = stockRow.currentStock - item.quantity;
      if (newStock < 0) {
        throw StateError(
          'Insufficient stock for product $productLocalId.',
        );
      }

      await (_db.update(_db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productLocalId) &
                  s.locationLocalId.equals(locationId),
            ))
          .write(
        ProductStockLevelsCompanion(
          currentStock: Value(newStock),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  @override
  Future<List<SalePayment>> getPaymentsForSale(String saleLocalId) async {
    final rows = await (_db.select(_db.salePayments)..where((p) => p.saleLocalId.equals(saleLocalId))).get();
    return rows.map((r) => r.toDomain()).toList();
  }
}
