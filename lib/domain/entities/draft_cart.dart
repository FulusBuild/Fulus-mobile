import 'sale.dart';
import 'sale_payment.dart';

/// The persisted, resumable cart — see tables.dart's `DraftCarts` table
/// doc comment for the full "why this exists separately from Sales"
/// reasoning. This is the domain-layer counterpart of that table; `sale_
/// draft.dart`'s `SaleDraft` remains what actually gets handed to
/// `SaleRepository.createSale` once checkout finishes — a `DraftCart`
/// is what exists *before* that moment, and
/// `DraftCartRepository.completeSale` is the bridge between the two.
class DraftCart {
  const DraftCart({
    required this.localId,
    required this.locationId,
    this.customerLocalId,
    this.wholeCartDiscount = 0.0,
    this.tax = 0.0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String localId;
  final String locationId;
  final String? customerLocalId;
  final double wholeCartDiscount;

  /// Same "not resolved by this module" status `Sale.tax`/checkout
  /// always had — Business Settings owns the VAT rate; this is
  /// whatever the caller already computed from it.
  final double tax;

  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class DraftCartItem {
  const DraftCartItem({
    required this.localId,
    required this.draftCartLocalId,
    this.productLocalId,
    this.description = '',
    required this.quantity,
    required this.unitPrice,
    this.costPriceAtSale = 0.0,
    this.lineDiscount = 0.0,
  });

  final String localId;
  final String draftCartLocalId;
  final String? productLocalId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double costPriceAtSale;
  final double lineDiscount;

  /// Raw, pre-discount — same convention `SaleItem.lineTotal` uses, for
  /// the same reason: this is what a cart-level subtotal needs to sum,
  /// with the discount subtracted out separately afterward.
  double get lineTotal => quantity * unitPrice;

  /// Converts to the [SaleItem] shape `SaleDraft`/`SaleRepository.
  /// createSale` actually expect, assigning the fresh identity a real
  /// sale line needs (a draft-cart-item's own `localId` doesn't carry
  /// forward — the finished sale gets entirely new item ids, keeping
  /// "which ids exist in Sales/SaleItems" simple: only ever real, synced
  /// or sync-pending rows, never a draft's leftover ids).
  SaleItem toSaleItem({required String newLocalId}) {
    return SaleItem(
      localId: newLocalId,
      productLocalId: productLocalId,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      costPriceAtSale: costPriceAtSale,
      lineDiscount: lineDiscount,
    );
  }
}

class DraftCartPayment {
  const DraftCartPayment({
    required this.localId,
    required this.draftCartLocalId,
    required this.method,
    required this.amount,
    required this.recordedAt,
  });

  final String localId;
  final String draftCartLocalId;
  final String method;
  final double amount;
  final DateTime recordedAt;

  /// Same fresh-identity reasoning as `DraftCartItem.toSaleItem`.
  /// `saleLocalId` stays null — the real sale doesn't exist yet at the
  /// point this is called; `toDriftCompanion`'s own `saleLocalId`
  /// parameter is what actually supplies it at write time.
  SalePayment toSalePayment({required String newLocalId}) {
    return SalePayment(
      localId: newLocalId,
      method: method,
      amount: amount,
      recordedAt: recordedAt,
    );
  }
}
