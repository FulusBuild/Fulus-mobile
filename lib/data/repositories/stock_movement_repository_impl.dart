import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/stock_movement_validation.dart' as validation;
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/stock_movement_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'stock_movement_mapper.dart';

class StockMovementRepositoryImpl implements StockMovementRepository {
  StockMovementRepositoryImpl({
    required AppDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final SyncQueue _syncQueue;

  Future<StockMovement> _record(StockMovement movement) async {
    await _db.transaction(() async {
      final current = await (_db.select(_db.productStockLevels)
            ..where((row) => row.productLocalId.equals(movement.productLocalId))
            ..where((row) => row.locationLocalId.equals(movement.locationId)))
          .getSingleOrNull();
      final currentStock = current?.currentStock ?? 0;
      final nextStock = switch (movement.movementType) {
        StockMovementType.stockIn => currentStock + movement.quantity!,
        StockMovementType.stockOut => currentStock - movement.quantity!,
        StockMovementType.adjustment => movement.newQuantity!,
        _ => throw StateError('Unsupported local stock movement type: ${movement.movementType}'),
      };
      if (nextStock < 0) throw StateError('Insufficient stock for product ${movement.productLocalId}.');
      await _db.into(_db.productStockLevels).insertOnConflictUpdate(
        ProductStockLevelsCompanion.insert(
          productLocalId: movement.productLocalId,
          locationLocalId: movement.locationId,
          currentStock: Value(nextStock),
          updatedAt: DateTime.now(),
          syncStatus: SyncStatus.pending,
        ),
      );
      await _db.into(_db.stockMovements).insert(movement.toDriftCompanion());
      await _syncQueue.enqueue(SyncTask.recordStockMovement(movement.localId));
    });
    return movement;
  }

  @override
  Future<StockMovement> recordStockIn(StockInDraft draft) {
    validation.validateMovementQuantity(draft.quantity);
    return _record(draft.toStockMovementEntity(localId: Ulid().toString()));
  }

  @override
  Future<StockMovement> recordStockOut(StockOutDraft draft) {
    validation.validateMovementQuantity(draft.quantity);
    return _record(draft.toStockMovementEntity(localId: Ulid().toString()));
  }

  @override
  Future<StockMovement> recordAdjustment(StockAdjustmentDraft draft) {
    validation.validateAdjustmentTarget(draft.newQuantity);
    validation.validateAdjustmentReason(draft.reason);
    return _record(draft.toStockMovementEntity(localId: Ulid().toString()));
  }

  @override
  Stream<List<StockMovement>> watchMovementsForLocation(String locationId) {
    final query = _db.select(_db.stockMovements)
      ..where((m) => m.deletedAt.isNull())
      ..where((m) => m.locationId.equals(locationId))
      ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<StockMovement?> getStockMovementById(String localId) async {
    final row = await (_db.select(_db.stockMovements)..where((m) => m.localId.equals(localId))).getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> markSettled({required String localId, String? operationId}) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)..where((q) => q.id.equals(operationId))).getSingleOrNull();
        if (current != null) {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'stock_movement', entityLocalId: localId, operationId: operationId, enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.stockMovements)..where((m) => m.localId.equals(localId))).write(
        StockMovementsCompanion(
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
          updatedAt: hasNewerMutation ? const Value.absent() : Value(DateTime.now()),
        ),
      );
    });
  }

  @override
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
  }) async {
    await _db.transaction(() async {
      final product = await (_db.select(_db.products)
            ..where((p) => p.serverId.equals(productServerId)))
          .getSingleOrNull();
      final location = await (_db.select(_db.locations)
            ..where((l) => l.serverId.equals(locationServerId)))
          .getSingleOrNull();
      if (product == null) throw StateError('Canonical stock movement $serverId references unknown product $productServerId.');
      if (location == null) throw StateError('Canonical stock movement $serverId references unknown location $locationServerId.');

      String? toLocationLocalId;
      if (toLocationServerId != null) {
        final toLocation = await (_db.select(_db.locations)
              ..where((l) => l.serverId.equals(toLocationServerId)))
            .getSingleOrNull();
        if (toLocation == null) throw StateError('Canonical stock movement $serverId references unknown destination location $toLocationServerId.');
        toLocationLocalId = toLocation.localId;
      }

      final existing = await (_db.select(_db.stockMovements)
            ..where((m) => m.serverId.equals(serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();
      final values = StockMovementsCompanion(
        serverId: Value(serverId),
        productLocalId: Value(product.localId),
        locationId: Value(location.localId),
        toLocationId: Value(toLocationLocalId),
        movementType: Value(movementType.wireValue),
        quantity: Value(quantity),
        newQuantity: Value(newQuantity),
        reason: Value(reason),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
        syncStatus: const Value(SyncStatus.settled),
      );
      if (existing == null) {
        await _db.into(_db.stockMovements).insert(
          StockMovementsCompanion.insert(
            localId: localId,
            serverId: Value(serverId),
            productLocalId: product.localId,
            locationId: location.localId,
            toLocationId: Value(toLocationLocalId),
            movementType: movementType.wireValue,
            quantity: Value(quantity),
            newQuantity: Value(newQuantity),
            reason: Value(reason),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            syncStatus: SyncStatus.settled,
          ),
        );
      } else {
        await (_db.update(_db.stockMovements)..where((m) => m.localId.equals(localId))).write(values);
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.stockMovements)..where((m) => m.serverId.equals(serverId))).getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.stockMovements)..where((m) => m.localId.equals(row.localId))).write(
      StockMovementsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
