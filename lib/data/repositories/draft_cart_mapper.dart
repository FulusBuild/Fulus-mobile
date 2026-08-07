import 'package:drift/drift.dart';

import '../../domain/entities/draft_cart.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension DraftCartToCompanion on DraftCart {
  DraftCartsCompanion toDriftCompanion() {
    return DraftCartsCompanion.insert(
      localId: localId,
      locationId: locationId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      customerLocalId: Value(customerLocalId),
      wholeCartDiscount: Value(wholeCartDiscount),
      tax: Value(tax),
      notes: Value(notes),
    );
  }
}

extension DraftCartRowToDomain on DraftCartRow {
  DraftCart toDomain() {
    return DraftCart(
      localId: localId,
      locationId: locationId,
      customerLocalId: customerLocalId,
      wholeCartDiscount: wholeCartDiscount,
      tax: tax,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension DraftCartItemToCompanion on DraftCartItem {
  DraftCartItemsCompanion toDriftCompanion({required String draftCartLocalId}) {
    return DraftCartItemsCompanion.insert(
      localId: localId,
      draftCartLocalId: draftCartLocalId,
      quantity: quantity,
      unitPrice: unitPrice,
      productLocalId: Value(productLocalId),
      description: Value(description),
      costPriceAtSale: Value(costPriceAtSale),
      lineDiscount: Value(lineDiscount),
    );
  }
}

extension DraftCartItemRowToDomain on DraftCartItemRow {
  DraftCartItem toDomain() {
    return DraftCartItem(
      localId: localId,
      draftCartLocalId: draftCartLocalId,
      productLocalId: productLocalId,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      costPriceAtSale: costPriceAtSale,
      lineDiscount: lineDiscount,
    );
  }
}

extension DraftCartPaymentToCompanion on DraftCartPayment {
  DraftCartPaymentsCompanion toDriftCompanion({required String draftCartLocalId}) {
    return DraftCartPaymentsCompanion.insert(
      localId: localId,
      draftCartLocalId: draftCartLocalId,
      method: method,
      amount: amount,
      recordedAt: recordedAt,
    );
  }
}

extension DraftCartPaymentRowToDomain on DraftCartPaymentRow {
  DraftCartPayment toDomain() {
    return DraftCartPayment(
      localId: localId,
      draftCartLocalId: draftCartLocalId,
      method: method,
      amount: amount,
      recordedAt: recordedAt,
    );
  }
}
