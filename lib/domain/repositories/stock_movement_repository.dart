import '../entities/stock_movement.dart';

abstract class StockMovementRepository {
  Future<StockMovement> recordStockIn(StockInDraft draft);
  Future<StockMovement> recordStockOut(StockOutDraft draft);
  Future<StockMovement> recordAdjustment(StockAdjustmentDraft draft);
  Stream<List<StockMovement>> watchMovementsForLocation(String locationId);
  Future<StockMovement?> getStockMovementById(String localId);
  Future<void> markSettled({required String localId});

  /// Applies a server-authoritative movement without creating an outbound
  /// sync task. Server product/location IDs are resolved to local foreign keys.
  Future<void> reconcileServerState({
    required String serverId,
    required String productServerId,
    required String locationServerId,
    String? toLocationServerId,
    required StockMovementType movementType,
    int? quantity,
    int? newQuantity,
    String? reason,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  Future<void> reconcileDeleted(String serverId);
}
