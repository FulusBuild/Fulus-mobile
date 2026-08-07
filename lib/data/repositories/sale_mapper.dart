import 'package:drift/drift.dart';

import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_payment.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

/// Domain -> Drift, for the local-write-first transaction in
/// SaleRepositoryImpl.createSale (Architecture Section 4). syncStatus is
/// always written as `pending` here — this extension is only ever used
/// at creation time, before anything has been synced; SaleRepositoryImpl
/// .markSynced is the only place that later moves a row to `settled`,
/// and it updates the existing row directly rather than reinserting
/// through this method.
extension SaleToCompanion on Sale {
  SalesCompanion toDriftCompanion() {
    return SalesCompanion.insert(
      localId: localId,
      clientReference: clientReference,
      locationId: locationId,
      saleDate: saleDate,
      subtotal: subtotal,
      total: total,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      invoiceNumber: Value(invoiceNumber),
      customerId: Value(customerId),
      cashierUserId: Value(cashierUserId),
      discount: Value(discount),
      wholeCartDiscount: Value(wholeCartDiscount),
      tax: Value(tax),
      amountPaid: Value(amountPaid),
      paymentMethod: Value(paymentMethod),
      notes: Value(notes),
      deletedAt: const Value(null),
    );
  }
}

/// Domain -> Drift for a single line item. Takes `saleLocalId`
/// explicitly, as a required parameter, rather than matching
/// Architecture Section 4's illustrative `item.toDriftCompanion()` call
/// with zero arguments — the domain SaleItem deliberately has no
/// saleLocalId field of its own (Section 4: items belong to a Sale
/// contextually, via its own `items` list, not by holding a redundant
/// back-reference in memory), so the one place that foreign key
/// actually needs to be supplied is here, at the point of writing to a
/// table that requires it.
extension SaleItemToCompanion on SaleItem {
  SaleItemsCompanion toDriftCompanion({required String saleLocalId}) {
    return SaleItemsCompanion.insert(
      localId: localId,
      saleLocalId: saleLocalId,
      quantity: quantity,
      unitPrice: unitPrice,
      costPriceAtSale: costPriceAtSale,
      productLocalId: Value(productLocalId),
      description: Value(description),
      lineDiscount: Value(lineDiscount),
    );
  }
}

/// Drift -> domain, the read direction. Takes the already-queried child
/// SaleItemRows rather than querying for them itself, since fetching
/// child rows is a database-level concern (SaleRepositoryImpl decides
/// how/when to query them) that this pure mapping function shouldn't
/// reach out and perform on its own.
extension SaleRowToDomain on SaleRow {
  Sale toDomain(List<SaleItemRow> items) {
    return Sale(
      localId: localId,
      serverId: serverId,
      clientReference: clientReference,
      invoiceNumber: invoiceNumber,
      customerId: customerId,
      locationId: locationId,
      cashierUserId: cashierUserId,
      saleDate: saleDate,
      subtotal: subtotal,
      wholeCartDiscount: wholeCartDiscount,
      discount: discount,
      tax: tax,
      total: total,
      amountPaid: amountPaid,
      paymentMethod: paymentMethod,
      notes: notes,
      items: items.map((row) => row.toDomain()).toList(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

extension SaleItemRowToDomain on SaleItemRow {
  SaleItem toDomain() {
    return SaleItem(
      localId: localId,
      productLocalId: productLocalId,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      costPriceAtSale: costPriceAtSale,
      lineDiscount: lineDiscount,
    );
  }
}

extension SalePaymentToCompanion on SalePayment {
  SalePaymentsCompanion toDriftCompanion({required String saleLocalId}) {
    return SalePaymentsCompanion.insert(
      localId: localId,
      saleLocalId: saleLocalId,
      method: method,
      amount: amount,
      recordedAt: recordedAt,
    );
  }
}

extension SalePaymentRowToDomain on SalePaymentRow {
  SalePayment toDomain() {
    return SalePayment(
      localId: localId,
      saleLocalId: saleLocalId,
      method: method,
      amount: amount,
      recordedAt: recordedAt,
    );
  }
}
