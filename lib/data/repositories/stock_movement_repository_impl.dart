import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/business_engine/stock_movement_validation.dart'
    as validation;
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

  /// Shared by all three record* methods below — the write-locally-then-
  /// enqueue shape is identical regardless of which of the three kinds
  /// this is; only how the [StockMovement] itself gets built differs
  /// (each *Draft's own toStockMovementEntity), which is why this takes
  /// an already-built entity rather than a draft.
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
      if (nextStock < 0) {
        throw StateError('Insufficient stock for product ${movement.productLocalId}.');
      }
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
    final localId = Ulid().toString();
    return _record(draft.toStockMovementEntity(localId: localId));
  }

  @override
  Future<StockMovement> recordStockOut(StockOutDraft draft) {
    validation.validateMovementQuantity(draft.quantity);
    final localId = Ulid().toString();
    return _record(draft.toStockMovementEntity(localId: localId));
  }

  @override
  Future<StockMovement> recordAdjustment(StockAdjustmentDraft draft) {
    validation.validateAdjustmentTarget(draft.newQuantity);
    validation.validateAdjustmentReason(draft.reason);
    final localId = Ulid().toString();
    return _record(draft.toStockMovementEntity(localId: localId));
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
    final row = await (_db.select(_db.stockMovements)
          ..where((m) => m.localId.equals(localId)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> markSettled({required String localId}) async {
    await (_db.update(_db.stockMovements)..where((m) => m.localId.equals(localId)))
        .write(
      StockMovementsCompanion(
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
