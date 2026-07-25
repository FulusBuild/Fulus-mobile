import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/stock_movements_api.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/stock_movement_repository.dart';
import '../sync_handler.dart';

class StockMovementSyncHandler implements SyncHandler {
  StockMovementSyncHandler({
    required AppDatabase db,
    required StockMovementsApi stockMovementsApi,
    required StockMovementRepository stockMovementRepository,
  })  : _db = db,
        _stockMovementsApi = stockMovementsApi,
        _stockMovementRepository = stockMovementRepository;

  final AppDatabase _db;
  final StockMovementsApi _stockMovementsApi;
  final StockMovementRepository _stockMovementRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      // No caller in this codebase enqueues 'update'/'delete' for
      // 'stock_movement' today — SyncTask.recordStockMovement is the
      // only factory that exists, and the ledger is append-only besides
      // (see tables.dart's own comment on StockMovements). Kept as an
      // explicit, honest failure rather than silently doing nothing if
      // this is ever somehow reached.
      throw StateError(
        'StockMovementSyncHandler does not support operation '
        '"${item.operation}" yet — only "create" is implemented.',
      );
    }

    final movement = await _stockMovementRepository.getStockMovementById(item.entityLocalId);
    if (movement == null) {
      throw StateError(
        'No local stock movement found for ${item.entityLocalId} — the '
        'queue item outlived its own row.',
      );
    }

    // Same gap, same reasoning as SaleSyncHandler._buildCreateDto's own
    // product lookup: Product has no sync/serverId-reconciliation built
    // yet in this phase (no ProductRepositoryImpl exists), so a locally-
    // recorded movement against a product that was never created or
    // pulled down through the mobile app has no server id to submit
    // against yet. Queried directly against the database here, exactly
    // like SaleSyncHandler does, rather than through ProductRepository
    // (whose interface has no such lookup method either, and which this
    // handler doesn't otherwise depend on).
    final product = await (_db.select(_db.products)
          ..where((p) => p.localId.equals(movement.productLocalId)))
        .getSingleOrNull();
    final productServerId = product?.serverId;
    if (productServerId == null) {
      throw StateError(
        'Product ${movement.productLocalId} has no serverId yet — '
        'product sync is not built in this phase, so this stock '
        'movement cannot be submitted server-side until that exists.',
      );
    }

    // The returned Product's current_stock/isLowStock/stockValue are
    // deliberately discarded here — see StockMovementsApi's own doc
    // comment on why: there is nowhere on-device to reconcile them TO
    // yet (no ProductRepositoryImpl in this phase). A real, honest gap,
    // not an oversight — same category as the product serverId gap
    // just above it.
    switch (movement.movementType) {
      case StockMovementType.stockIn:
        await _stockMovementsApi.stockIn(
          productId: productServerId,
          dto: movement.toStockInDto(clientReference: movement.localId),
        );
      case StockMovementType.stockOut:
        await _stockMovementsApi.stockOut(
          productId: productServerId,
          dto: movement.toStockOutDto(clientReference: movement.localId),
        );
      case StockMovementType.adjustment:
        await _stockMovementsApi.adjustStock(
          productId: productServerId,
          dto: movement.toStockAdjustmentDto(clientReference: movement.localId),
        );
      case StockMovementType.sale:
        // Genuinely unreachable through any real write path today —
        // StockMovementRepository has no method that ever constructs a
        // StockMovement with this type (see its own doc comment). Not
        // handled as a silent no-op: if this is ever somehow reached,
        // that means something bypassed the repository entirely, which
        // is a programming error worth surfacing loudly, not swallowing.
        throw StateError(
          'StockMovementSyncHandler received a "sale" movement type for '
          '${movement.localId} — sale movements are created '
          'automatically server-side as a byproduct of a sale and must '
          'never be submitted by mobile directly.',
        );
    }

    await _stockMovementRepository.markSettled(localId: movement.localId);
  }
}
