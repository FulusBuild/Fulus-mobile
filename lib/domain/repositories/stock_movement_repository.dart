import '../../core/money/money.dart';
import '../entities/stock_movement.dart';

abstract class StockMovementRepository {
  /// Records Stock In and all optional purchase metadata as one local
  /// transaction. If any part fails, stock, the movement, product metadata,
  /// outbox entries, and supplier credit all roll back together.
  Future<StockMovement> recordStockIn(
    StockInDraft draft, {
    Money? costPrice,
    String? supplierLocalId,
    bool onAccount = false,
  });
  Future<StockMovement> recordStockOut(StockOutDraft draft);
  Future<StockMovement> recordAdjustment(StockAdjustmentDraft draft);
  Stream<List<StockMovement>> watchMovementsForLocation(String locationId);
  Future<StockMovement?> getStockMovementById(String localId);
  Future<void> markSettled({required String localId, String? operationId});

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
