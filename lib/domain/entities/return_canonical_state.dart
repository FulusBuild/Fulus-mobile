class ReturnCanonicalState {
  const ReturnCanonicalState({
    required this.serverId,
    required this.originalSaleServerId,
    required this.status,
    required this.returnReason,
    required this.refundAmount,
    required this.refundMethod,
    required this.inventoryRestored,
    required this.isVoid,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  final String serverId;
  final String originalSaleServerId;
  final String status;
  final String returnReason;
  final double refundAmount;
  final String refundMethod;
  final bool inventoryRestored;
  final bool isVoid;
  final List<ReturnCanonicalItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
}

class ReturnCanonicalItem {
  const ReturnCanonicalItem({
    required this.serverId,
    required this.productServerId,
    required this.quantity,
  });

  final String serverId;
  final String productServerId;
  final int quantity;
}
