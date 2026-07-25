import 'package:drift/drift.dart';

import '../../domain/entities/stock_movement.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension StockMovementToCompanion on StockMovement {
  StockMovementsCompanion toDriftCompanion() {
    return StockMovementsCompanion.insert(
      localId: localId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: movementType.wireValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      quantity: Value(quantity),
      newQuantity: Value(newQuantity),
      reason: Value(reason),
      deletedAt: const Value(null),
    );
  }
}

extension StockMovementRowToDomain on StockMovementRow {
  StockMovement toDomain() {
    return StockMovement(
      localId: localId,
      serverId: serverId,
      productLocalId: productLocalId,
      locationId: locationId,
      movementType: StockMovementType.fromWireValue(movementType),
      quantity: quantity,
      newQuantity: newQuantity,
      reason: reason,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
