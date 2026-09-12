import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/stock_movement_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/stock_movement.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late StockMovementRepositoryImpl repository;

  const locationId = 'loc-1';
  const productLocalId = 'prod-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = StockMovementRepositoryImpl(db: db, syncQueue: syncQueue);

    // StockMovements.locationId and .productLocalId are both real,
    // non-nullable FK references (unlike IncomeRecords/Expenses'
    // nullable locationId) — a row must exist in both Locations and
    // Products before any movement referencing them can be inserted,
    // since PRAGMA foreign_keys = ON applies to test databases the same
    // as the real one.
    await db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          localId: productLocalId,
          name: 'USB-C Cable',
          sku: 'CAB-USBC',
          costPrice: 500.0,
          sellingPrice: 1200.0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  group('recordStockIn', () {
    test('writes a movement with quantity set and newQuantity null', () async {
      final result = await repository.recordStockIn(
        const StockInDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          quantity: 20,
          reason: 'New delivery',
        ),
      );

      expect(result.movementType, StockMovementType.stockIn);
      expect(result.quantity, 20);
      expect(result.newQuantity, isNull);

      final row = await (db.select(db.stockMovements)
            ..where((m) => m.localId.equals(result.localId)))
          .getSingle();
      expect(row.movementType, 'in');
      expect(row.quantity, 20);
      expect(row.newQuantity, isNull);
      final stock = await (db.select(db.productStockLevels)..where((s) => s.productLocalId.and([s.productLocalId.equals(productLocalId), s.locationLocalId.equals(locationId)]))).getSingle();
      expect(stock.currentStock, 20);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'stock_movement');
      expect(queued.single.operation, 'create');
      expect(queued.single.entityLocalId, result.localId);
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });
  });

  group('recordStockOut', () {
    test('writes a movement with quantity set and newQuantity null', () async {
      final result = await repository.recordStockOut(
        const StockOutDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          quantity: 5,
          reason: 'Damaged',
        ),
      );

      expect(result.movementType, StockMovementType.stockOut);
      expect(result.quantity, 5);
      expect(result.newQuantity, isNull);
    });
  });

  group('recordAdjustment', () {
    test('writes a movement with newQuantity set and quantity null', () async {
      final result = await repository.recordAdjustment(
        const StockAdjustmentDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          newQuantity: 42,
          reason: 'Recount',
        ),
      );

      expect(result.movementType, StockMovementType.adjustment);
      expect(result.newQuantity, 42);
      expect(result.quantity, isNull);
      expect(result.reason, 'Recount');
      final stock = await (db.select(db.productStockLevels)..where((s) => s.productLocalId.and([s.productLocalId.equals(productLocalId), s.locationLocalId.equals(locationId)]))).getSingle();
      expect(stock.currentStock, 42);
    });
  });

  group('local stock safety', () {
    test('rejects stock-out that would make local stock negative and writes nothing', () async {
      await db.into(db.productStockLevels).insert(ProductStockLevelsCompanion.insert(
        productLocalId: productLocalId,
        locationLocalId: locationId,
        currentStock: const Value(2),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.settled,
      ));
      await expectLater(
        repository.recordStockOut(const StockOutDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          quantity: 3,
        )),
        throwsStateError,
      );
      expect(await db.select(db.stockMovements).get(), isEmpty);
      final stock = await (db.select(db.productStockLevels)..where((s) => s.productLocalId.and([s.productLocalId.equals(productLocalId), s.locationLocalId.equals(locationId)]))).getSingle();
      expect(stock.currentStock, 2);
    });
  });

  group('watchMovementsForLocation', () {
    test('emits only movements for the given location', () async {
      await repository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-2',
            name: 'Other Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      await repository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: 'loc-2', quantity: 10),
      );

      final emitted = await repository.watchMovementsForLocation(locationId).first;

      expect(emitted, hasLength(1));
      expect(emitted.single.quantity, 20);
    });
  });

  group('getStockMovementById', () {
    test('returns the matching movement', () async {
      final created = await repository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      final fetched = await repository.getStockMovementById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getStockMovementById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('markSettled', () {
    test('sets syncStatus to settled without touching serverId', () async {
      final created = await repository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      await repository.markSettled(localId: created.localId);

      final row = await (db.select(db.stockMovements)
            ..where((m) => m.localId.equals(created.localId)))
          .getSingle();
      expect(row.syncStatus, SyncStatus.settled);
      // No serverId ever gets set for a stock movement — see
      // StockMovementRepository.markSettled's own doc comment on why
      // none of the three write endpoints ever return one for the
      // movement itself.
      expect(row.serverId, isNull);
    });
  });
}
