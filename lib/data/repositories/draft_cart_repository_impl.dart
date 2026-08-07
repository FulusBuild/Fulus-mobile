import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/draft_cart_aggregation.dart' as aggregation;
import '../../domain/entities/draft_cart.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_draft.dart';
import '../../domain/repositories/draft_cart_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/sale_repository.dart';
import '../local/database/database.dart';
import 'draft_cart_mapper.dart';

class DraftCartRepositoryImpl implements DraftCartRepository {
  DraftCartRepositoryImpl({
    required AppDatabase db,
    required ProductRepository productRepository,
    required SaleRepository saleRepository,
  })  : _db = db,
        _productRepository = productRepository,
        _saleRepository = saleRepository;

  final AppDatabase _db;
  final ProductRepository _productRepository;
  final SaleRepository _saleRepository;

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
    final amountPaid = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final paymentMethod = aggregation.aggregatePaymentMethod(
      payments.map((p) => p.method).toList(),
    );

    final saleDraft = SaleDraft(
      items: items,
      locationId: draft.locationId,
      amountPaid: amountPaid,
      customerId: draft.customerLocalId,
      discount: discount,
      tax: draft.tax,
      paymentMethod: paymentMethod,
      notes: draft.notes,
      payments: payments,
    );

    final sale = await _saleRepository.createSale(saleDraft);
    await clearDraft(draftCartLocalId);
    return sale;
  }
}
