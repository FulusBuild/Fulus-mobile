import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/draft_cart_aggregation.dart' as aggregation;
import '../../core/diagnostics/diagnostic_logger.dart';
import '../../core/diagnostics/models/diagnostic_enums.dart';
import '../../domain/entities/draft_cart.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_draft.dart';
import '../../domain/repositories/draft_cart_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/sale_repository.dart';
import '../local/database/database.dart';
import 'draft_cart_mapper.dart';
import '../../sync/sync_queue.dart';

class DraftCartRepositoryImpl implements DraftCartRepository {
  DraftCartRepositoryImpl({
    required AppDatabase db,
    required ProductRepository productRepository,
    required SaleRepository saleRepository,
    SyncQueue? syncQueue,
    DiagnosticLogger? diagnosticLogger,
  })  : _db = db,
        _productRepository = productRepository,
        _saleRepository = saleRepository,
        _syncQueue = syncQueue,
        _diagnosticLogger = diagnosticLogger;

  final AppDatabase _db;
  final ProductRepository _productRepository;
  final SaleRepository _saleRepository;
  final SyncQueue? _syncQueue;

  /// Optional, same reasoning as SaleRepositoryImpl's own
  /// `_diagnosticLogger` field. This is the class where the "Complete
  /// Sale" multi-step operation the diagnostic-system brief's Section 5
  /// describes actually lives (see [completeSale] below) — everywhere
  /// else in this file stays uninstrumented, since nothing else here is
  /// a multi-step business operation in the same sense.
  final DiagnosticLogger? _diagnosticLogger;

  /// Draft carts never sync. They are therefore fenced while the selected
  /// business context is changing instead of being silently destroyed.
  Future<void> assertNoDraftCartMutationDuringSwitch() async {
    _syncQueue?.ensureLocalMutationAllowed();
  }

  Future<void> clearAllDraftCarts() async {
    await _db.transaction(() async {
      await _db.delete(_db.draftCartItems).go();
      await _db.delete(_db.draftCartPayments).go();
      await _db.delete(_db.draftCarts).go();
    });
  }

  Future<DraftCartRow> _requireDraftCart(String localId) async {
    final row = await (_db.select(_db.draftCarts)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(localId, 'draftCartLocalId', 'no such draft cart');
    }
    return row;
  }

  Future<void> _touch(String draftCartLocalId) async {
    await (_db.update(_db.draftCarts)
          ..where((c) => c.localId.equals(draftCartLocalId)))
        .write(DraftCartsCompanion(updatedAt: Value(DateTime.now())));
  }

  @override
  Future<DraftCart> getOrCreateDraftCart({required String locationId}) async {
    _syncQueue.ensureLocalMutationAllowed();
    final existing = await (_db.select(_db.draftCarts)
          ..where((c) => c.locationId.equals(locationId)))
        .getSingleOrNull();
    if (existing != null) return existing.toDomain();

    final location = await (_db.select(_db.locations)
          ..where((l) => l.localId.equals(locationId)))
        .getSingleOrNull();
    if (location == null) {
      throw ArgumentError.value(
        locationId,
        'locationId',
        'no such location — seed a locations row before creating a draft cart for it',
      );
    }

    final now = DateTime.now();
    final draft = DraftCart(
      localId: Ulid().toString(),
      locationId: locationId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.draftCarts).insert(draft.toDriftCompanion());
    return draft;
  }

  @override
  Future<DraftCartItem> addItem({
    required String draftCartLocalId,
    String? productLocalId,
    String? description,
    required int quantity,
    double? unitPrice,
    double lineDiscount = 0.0,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be > 0');
    }

    double resolvedUnitPrice;
    double costPriceAtSale;
    String resolvedDescription;

    if (productLocalId != null) {
      final cartRow = await _requireDraftCart(draftCartLocalId);
      final productWithStock = await _productRepository.getProductById(
        productLocalId,
        locationId: cartRow.locationId,
      );
      if (productWithStock == null) {
        throw ArgumentError.value(productLocalId, 'productLocalId', 'no such product');
      }
      final product = productWithStock.product;
      resolvedUnitPrice = unitPrice ?? product.sellingPrice;
      costPriceAtSale = product.costPrice;
      resolvedDescription = description ?? product.name;
    } else {
      // Quick Sale — no product to fall back to a price or name from.
      if (unitPrice == null) {
        throw ArgumentError(
          'unitPrice is required for a Quick Sale item (no productLocalId)',
        );
      }
      // Defense-in-depth fix (business-logic audit): QuickSaleSheet
      // already checks `price <= 0` before ever calling this (see that
      // widget's own validation), so this specific path wasn't directly
      // reachable through the normal UI — but nothing at this layer
      // caught it either, relying entirely on that one UI check. Mirrors
      // the `quantity <= 0` guard immediately above for the same reason:
      // a negative or zero price here would corrupt lineTotal, subtotal,
      // and (if paid) amountPaid for the whole sale.
      if (unitPrice <= 0) {
        throw ArgumentError.value(unitPrice, 'unitPrice', 'must be > 0');
      }
      if (description == null || description.trim().isEmpty) {
        throw ArgumentError(
          'description is required for a Quick Sale item (no productLocalId)',
        );
      }
      resolvedUnitPrice = unitPrice;
      costPriceAtSale = 0.0;
      resolvedDescription = description;
    }

    if (lineDiscount < 0 || lineDiscount > quantity * resolvedUnitPrice) {
      throw ArgumentError.value(
        lineDiscount,
        'lineDiscount',
        'must be between 0 and this line\'s own value',
      );
    }

    final item = DraftCartItem(
      localId: Ulid().toString(),
      draftCartLocalId: draftCartLocalId,
      productLocalId: productLocalId,
      description: resolvedDescription,
      quantity: quantity,
      unitPrice: resolvedUnitPrice,
      costPriceAtSale: costPriceAtSale,
      lineDiscount: lineDiscount,
    );
    await _db
        .into(_db.draftCartItems)
        .insert(item.toDriftCompanion(draftCartLocalId: draftCartLocalId));
    await _touch(draftCartLocalId);
    return item;
  }

  Future<DraftCartItemRow> _requireItemRow(String itemLocalId) async {
    final row = await (_db.select(_db.draftCartItems)
          ..where((i) => i.localId.equals(itemLocalId)))
        .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(itemLocalId, 'itemLocalId', 'no such draft cart item');
    }
    return row;
  }

  @override
  Future<DraftCartItem> updateItemQuantity({
    required String itemLocalId,
    required int quantity,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be > 0');
    }
    final existing = (await _requireItemRow(itemLocalId)).toDomain();
    await (_db.update(_db.draftCartItems)..where((i) => i.localId.equals(itemLocalId)))
        .write(DraftCartItemsCompanion(quantity: Value(quantity)));
    await _touch(existing.draftCartLocalId);
    return DraftCartItem(
      localId: existing.localId,
      draftCartLocalId: existing.draftCartLocalId,
      productLocalId: existing.productLocalId,
      description: existing.description,
      quantity: quantity,
      unitPrice: existing.unitPrice,
      costPriceAtSale: existing.costPriceAtSale,
      lineDiscount: existing.lineDiscount,
    );
  }

  @override
  Future<DraftCartItem> updateItemDiscount({
    required String itemLocalId,
    required double lineDiscount,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    final existing = (await _requireItemRow(itemLocalId)).toDomain();
    if (lineDiscount < 0 || lineDiscount > existing.quantity * existing.unitPrice) {
      throw ArgumentError.value(
        lineDiscount,
        'lineDiscount',
        'must be between 0 and this line\'s own value',
      );
    }
    await (_db.update(_db.draftCartItems)..where((i) => i.localId.equals(itemLocalId)))
        .write(DraftCartItemsCompanion(lineDiscount: Value(lineDiscount)));
    await _touch(existing.draftCartLocalId);
    return DraftCartItem(
      localId: existing.localId,
      draftCartLocalId: existing.draftCartLocalId,
      productLocalId: existing.productLocalId,
      description: existing.description,
      quantity: existing.quantity,
      unitPrice: existing.unitPrice,
      costPriceAtSale: existing.costPriceAtSale,
      lineDiscount: lineDiscount,
    );
  }

  @override
  Future<void> removeItem(String itemLocalId) async {
    _syncQueue.ensureLocalMutationAllowed();
    final existing = await _requireItemRow(itemLocalId);
    await (_db.delete(_db.draftCartItems)..where((i) => i.localId.equals(itemLocalId)))
        .go();
    await _touch(existing.draftCartLocalId);
  }

  @override
  Future<DraftCart> setCustomer({
    required String draftCartLocalId,
    required String? customerLocalId,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    await _requireDraftCart(draftCartLocalId);
    await (_db.update(_db.draftCarts)..where((c) => c.localId.equals(draftCartLocalId)))
        .write(
      DraftCartsCompanion(
        customerLocalId: Value(customerLocalId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await _requireDraftCart(draftCartLocalId)).toDomain();
  }

  @override
  Future<DraftCart> setWholeCartDiscount({
    required String draftCartLocalId,
    required double discount,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    if (discount < 0) {
      throw ArgumentError.value(discount, 'discount', 'must be ≥ 0');
    }
    await _requireDraftCart(draftCartLocalId);
    await (_db.update(_db.draftCarts)..where((c) => c.localId.equals(draftCartLocalId)))
        .write(
      DraftCartsCompanion(
        wholeCartDiscount: Value(discount),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await _requireDraftCart(draftCartLocalId)).toDomain();
  }

  @override
  Future<DraftCart> setTax({
    required String draftCartLocalId,
    required double tax,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    if (tax < 0) {
      throw ArgumentError.value(tax, 'tax', 'must be ≥ 0');
    }
    await _requireDraftCart(draftCartLocalId);
    await (_db.update(_db.draftCarts)..where((c) => c.localId.equals(draftCartLocalId)))
        .write(DraftCartsCompanion(tax: Value(tax), updatedAt: Value(DateTime.now())));
    return (await _requireDraftCart(draftCartLocalId)).toDomain();
  }

  @override
  Future<DraftCart> addPayment({
    required String draftCartLocalId,
    required String method,
    required double amount,
  }) async {
    _syncQueue.ensureLocalMutationAllowed();
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }
    await _requireDraftCart(draftCartLocalId);
    final payment = DraftCartPayment(
      localId: Ulid().toString(),
      draftCartLocalId: draftCartLocalId,
      method: method,
      amount: amount,
      recordedAt: DateTime.now(),
    );
    await _db
        .into(_db.draftCartPayments)
        .insert(payment.toDriftCompanion(draftCartLocalId: draftCartLocalId));
    await _touch(draftCartLocalId);
    return (await _requireDraftCart(draftCartLocalId)).toDomain();
  }

  @override
  Future<void> removePayment(String paymentLocalId) async {
    _syncQueue.ensureLocalMutationAllowed();
    final row = await (_db.select(_db.draftCartPayments)
          ..where((p) => p.localId.equals(paymentLocalId)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.draftCartPayments)
          ..where((p) => p.localId.equals(paymentLocalId)))
        .go();
    await _touch(row.draftCartLocalId);
  }

  @override
  Future<DraftCart> clearDraft(String draftCartLocalId) async {
    _syncQueue.ensureLocalMutationAllowed();
    await _requireDraftCart(draftCartLocalId);
    return _db.transaction(() async {
      await (_db.delete(_db.draftCartItems)
            ..where((i) => i.draftCartLocalId.equals(draftCartLocalId)))
          .go();
      await (_db.delete(_db.draftCartPayments)
            ..where((p) => p.draftCartLocalId.equals(draftCartLocalId)))
          .go();
      await (_db.update(_db.draftCarts)
            ..where((c) => c.localId.equals(draftCartLocalId)))
          .write(
        DraftCartsCompanion(
          customerLocalId: const Value(null),
          wholeCartDiscount: const Value(0.0),
          tax: const Value(0.0),
          notes: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (await _requireDraftCart(draftCartLocalId)).toDomain();
    });
  }

  @override
  Stream<DraftCart?> watchDraftCart(String draftCartLocalId) {
    final query = _db.select(_db.draftCarts)
      ..where((c) => c.localId.equals(draftCartLocalId));
    return query.watchSingleOrNull().map((row) => row?.toDomain());
  }

  @override
  Stream<List<DraftCartItem>> watchItems(String draftCartLocalId) {
    final query = _db.select(_db.draftCartItems)
      ..where((i) => i.draftCartLocalId.equals(draftCartLocalId));
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Stream<List<DraftCartPayment>> watchPayments(String draftCartLocalId) {
    final query = _db.select(_db.draftCartPayments)
      ..where((p) => p.draftCartLocalId.equals(draftCartLocalId));
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Sale> completeSale(String draftCartLocalId) async {
    _syncQueue.ensureLocalMutationAllowed();
    // The "Complete Sale" operation the diagnostic-system brief's own
    // Section 5 uses as its worked example — stages named to match what
    // this method actually does (audited directly, not copied from the
    // brief's illustrative 8-step list, which described a shape this
    // codebase's real implementation doesn't have — e.g. there is no
    // separate "validate products" step here; a product that no longer
    // exists surfaces as a foreign-key failure inside "Persist sale"
    // instead, which RootCauseEngine's ForeignKeyViolationRule already
    // accounts for).
    final op = _diagnosticLogger?.startOperation(
      operation: 'completeSale',
      component: 'DraftCartRepositoryImpl',
      category: DiagnosticCategory.sales,
      screen: 'SellScreen',
      stages: const ['Validate cart', 'Build sale', 'Persist sale', 'Clear cart'],
      context: {'Draft cart ID': draftCartLocalId},
    );
    try {
      op?.stage('Validate cart');
      final draft = await _requireDraftCart(draftCartLocalId);
      final itemRows = await (_db.select(_db.draftCartItems)
            ..where((i) => i.draftCartLocalId.equals(draftCartLocalId)))
          .get();
      if (itemRows.isEmpty) {
        throw StateError('A sale must have at least one item.');
      }
      final paymentRows = await (_db.select(_db.draftCartPayments)
            ..where((p) => p.draftCartLocalId.equals(draftCartLocalId)))
          .get();

      op?.stage('Build sale');
      final items = itemRows
          .map((row) => row.toDomain().toSaleItem(newLocalId: Ulid().toString()))
          .toList();
      final payments = paymentRows
          .map((row) => row.toDomain().toSalePayment(newLocalId: Ulid().toString()))
          .toList();

      final discount = aggregation.combineDiscount(
        wholeCartDiscount: draft.wholeCartDiscount,
        lineDiscounts: items.map((i) => i.lineDiscount).toList(),
      );
      // Bug fix ("Paid in full" regression) — see computeCashAmountPaid's
      // own doc comment in draft_cart_aggregation.dart for the full
      // story: this used to sum every leg indiscriminately, which made
      // a split sale with a credit leg persist as amountPaid == total.
      final amountPaid = aggregation.computeCashAmountPaid(
        payments.map((p) => (method: p.method, amount: p.amount)).toList(),
      );
      final paymentMethod = aggregation.aggregatePaymentMethod(
        payments.map((p) => p.method).toList(),
      );

      final saleDraft = SaleDraft(
        items: items,
        locationId: draft.locationId,
        amountPaid: amountPaid,
        customerId: draft.customerLocalId,
        discount: discount,
        wholeCartDiscount: draft.wholeCartDiscount,
        tax: draft.tax,
        paymentMethod: paymentMethod,
        notes: draft.notes,
        payments: payments,
      );
      op?.addContext({
        'Item count': '${items.length}',
        if (paymentMethod != null) 'Payment method': paymentMethod,
      });

      // Everything from here on runs in one transaction so it can only
      // succeed or fail as a whole. createSale() and clearDraft() each
      // open their own _db.transaction() internally, which nests inside
      // this one rather than committing separately — so does the sync
      // enqueue createSale() triggers on the way out. Before this, a
      // failure anywhere after the sale itself was written (clearing the
      // draft, enqueueing it for sync) could leave a real, committed sale
      // behind while the caller still saw an exception — and since
      // nothing tied a retry back to this specific draft, retrying from
      // the same cart created a second, duplicate sale. Now, any failure
      // in this block rolls the sale back too, so "the sale didn't go
      // through" is true whenever this throws.
      op?.stage('Persist sale');
      final sale = await _db.transaction(() async {
        final createdSale = await _saleRepository.createSale(saleDraft);
        op?.stage('Clear cart');
        await clearDraft(draftCartLocalId);
        return createdSale;
      });
      op?.complete();
      return sale;
    } catch (error, stackTrace) {
      // Captured here, then rethrown completely unchanged — see this
      // class's own header note and DiagnosticOperation's header
      // comment in diagnostic_logger.dart. PaymentScreen's existing
      // `catch (_)` (payment_screen.dart's own `_completeSale`) is
      // untouched by this addition: it still catches the same
      // exception, still preserves the cart, still shows the same
      // generic message — the difference this instrumentation makes is
      // that a real DiagnosticEvent now exists to explain *why*, in
      // More -> Diagnostics, instead of that information having been
      // silently discarded the moment `catch (_)` ran.
      unawaited(op?.fail(error, stackTrace));
      rethrow;
    }
  }
}
