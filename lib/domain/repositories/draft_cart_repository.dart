import '../entities/draft_cart.dart';
import '../entities/sale.dart';

/// The actual mechanism behind Decision 14 ("Sell always resumes an
/// in-progress cart"). See tables.dart's `DraftCarts` doc comment for
/// why this is entirely separate from `SaleRepository`.
abstract class DraftCartRepository {
  /// Returns the existing draft for [locationId] if one exists, or
  /// creates a fresh empty one. Called every time the Sell screen
  /// opens — the UI never has to know itself whether it's resuming or
  /// starting fresh.
  Future<DraftCart> getOrCreateDraftCart({required String locationId});

  /// [productLocalId] null means a Quick Sale line (Volume 5); when
  /// null, [description] and [unitPrice] are required — there's no
  /// product to fall back to either from. When [productLocalId] is
  /// given and [unitPrice] is omitted, resolves to the product's
  /// current `sellingPrice`, matching the backend's own
  /// `SaleItemCreate.unit_price` fallback exactly.
  Future<DraftCartItem> addItem({
    required String draftCartLocalId,
    String? productLocalId,
    String? description,
    required int quantity,
    double? unitPrice,
    double lineDiscount,
  });

  Future<DraftCartItem> updateItemQuantity({
    required String itemLocalId,
    required int quantity,
  });

  Future<DraftCartItem> updateItemDiscount({
    required String itemLocalId,
    required double lineDiscount,
  });

  /// Volume 5: "Removing a line is a left swipe; every removal shows a
  /// brief 'Undo' immediately after." The Undo affordance is a UI
  /// concern (show a toast, re-call addItem if tapped); this just
  /// removes the line.
  Future<void> removeItem(String itemLocalId);

  Future<DraftCart> setCustomer({
    required String draftCartLocalId,
    required String? customerLocalId,
  });

  Future<DraftCart> setWholeCartDiscount({
    required String draftCartLocalId,
    required double discount,
  });

  /// Not resolved by this repository — see `DraftCart.tax`'s own doc
  /// comment. The caller supplies the already-computed amount.
  Future<DraftCart> setTax({
    required String draftCartLocalId,
    required double tax,
  });

  Future<DraftCart> addPayment({
    required String draftCartLocalId,
    required String method,
    required double amount,
  });

  Future<void> removePayment(String paymentLocalId);

  /// Volume 5, Decision 14: "an explicit 'clear cart' action always
  /// available if a fresh start is actually wanted." Removes every item
  /// and payment and resets discount/customer/notes/tax — the
  /// `DraftCarts` row itself is kept (still the one `getOrCreateDraftCart`
  /// will find next), not deleted and recreated.
  Future<DraftCart> clearDraft(String draftCartLocalId);

  Stream<DraftCart?> watchDraftCart(String draftCartLocalId);

  Stream<List<DraftCartItem>> watchItems(String draftCartLocalId);

  Stream<List<DraftCartPayment>> watchPayments(String draftCartLocalId);

  /// The bridge from a [DraftCart] to a real, synced [Sale]. Reads the
  /// draft and its items/payments, aggregates the whole-cart + line
  /// discounts into one `discount` (`core/business_engine/
  /// draft_cart_aggregation.dart`'s `combineDiscount`) and the payment
  /// legs into one `paymentMethod`/`amountPaid`
  /// (`aggregatePaymentMethod`), builds a `SaleDraft`, and calls the
  /// existing `SaleRepository.createSale` — nothing about how a sale
  /// actually gets created or synced changes; this only builds the
  /// input it expects. Clears the draft cart on success, so the next
  /// `getOrCreateDraftCart` starts fresh.
  Future<Sale> completeSale(String draftCartLocalId);
}
