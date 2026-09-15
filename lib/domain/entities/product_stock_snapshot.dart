/// Server-authoritative stock for one product at one server location.
class ProductStockSnapshot {
  const ProductStockSnapshot({
    required this.locationServerId,
    required this.currentStock,
    required this.updatedAt,
  });

  final String locationServerId;
  final int currentStock;
  final DateTime updatedAt;
}
