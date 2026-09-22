class SaleCanonicalState {
  const SaleCanonicalState({
    required this.serverId,
    required this.clientReference,
    required this.invoiceNumber,
    required this.customerServerId,
    required this.locationServerId,
    required this.cashierUserId,
    required this.saleDate,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    required this.paymentMethod,
    required this.notes,
    required this.items,
    required this.payments,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String serverId;
  final String clientReference;
  final String? invoiceNumber;
  final String? customerServerId;
  final String locationServerId;
  final String? cashierUserId;
  final DateTime saleDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;
  final String? paymentMethod;
  final String? notes;
  final List<SaleCanonicalItem> items;
  final List<SaleCanonicalPayment> payments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class SaleCanonicalItem {
  const SaleCanonicalItem({
    required this.serverId,
    required this.productServerId,
    this.description = '',
    required this.quantity,
    required this.unitPrice,
    required this.costPriceAtSale,
    required this.lineTotal,
  });

  final String serverId;
  final String? productServerId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double costPriceAtSale;
  final double lineTotal;
}

class SaleCanonicalPayment {
  const SaleCanonicalPayment({
    required this.serverId,
    required this.method,
    required this.amount,
    required this.recordedAt,
  });

  final String serverId;
  final String method;
  final double amount;
  final DateTime recordedAt;
}
