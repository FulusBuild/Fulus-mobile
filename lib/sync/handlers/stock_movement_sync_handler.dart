import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/stock_movements_api.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_movement_repository.dart';
import '../sync_handler.dart';

class StockMovementSyncHandler implements SyncHandler {
  StockMovementSyncHandler({
    required AppDatabase db,
    required StockMovementsApi stockMovementsApi,
    required StockMovementRepository stockMovementRepository,
    required ProductRepository productRepository,
  })  : _db = db,
        _stockMovementsApi = stockMovementsApi,
        _stockMovementRepository = stockMovementRepository,
        _productRepository = productRepository;

  final AppDatabase _db;
  final StockMovementsApi _stockMovementsApi;
  final StockMovementRepository _stockMovementRepository;
  final ProductRepository _productRepository;

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
    // product lookup: this device needs the product's SERVER id
    // (POST /products/{server_id}/...), not its local one. Queried
    // directly against the database here, exactly like SaleSyncHandler
    // does, rather than through ProductRepository (whose interface has
    // no such single-id-lookup-returning-raw-serverId method — its read
    // methods return ProductWithStock, joined against a location, which
    // is more than this needs).
    //
    // CORRECTED note on reachability: this used to be a gap expected to
    // trigger often, back when nothing populated a product's serverId
    // at all. Now that ProductRepositoryImpl.syncFromServer exists, a
    // Products row can only ever exist locally as a direct consequence
    // of a real server-side product being pulled down — and that pull
    // always sets localId == serverId (see ProductResponseDtoToCompanion
    // .toDriftCompanion's own comment). So a StockMovement can only ever
    // reference a productLocalId that already has a serverId, by
    // construction (real FK constraint —
    // StockMovements.productLocalId references Products — plus that
    // invariant). This check should be unreachable in practice now,
    // same category as the .sale/.transfer switch cases below — kept as
    // a loud failure rather than removed, in case that invariant is
    // ever violated.
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

    late final ProductResponseDto response;
    switch (movement.movementType) {
      case StockMovementType.stockIn:
        response = await _stockMovementsApi.stockIn(
          productId: productServerId,
          dto: movement.toStockInDto(clientReference: movement.localId),
        );
      case StockMovementType.stockOut:
        response = await _stockMovementsApi.stockOut(
          productId: productServerId,
          dto: movement.toStockOutDto(clientReference: movement.localId),
        );
      case StockMovementType.adjustment:
        response = await _stockMovementsApi.adjustStock(
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
      case StockMovementType.transfer:
        // Also genuinely unreachable today, but for a different reason
        // than .sale above: StockMovementType.transfer is a real,
        // intended Phase 2 feature (Product Design Bible Volume 6,
        // Decision 21; Architecture Section 7a), not a mistake — see its
        // own doc comment. It's unreachable here specifically because no
        // backend endpoint exists yet to call (verified directly,
        // grepped the whole backend, nothing) and
        // StockMovementRepository has no recordTransfer method for the
        // same reason — building one now would mean calling an endpoint
        // that doesn't exist. This case exists so the switch stays
        // exhaustive as the enum grows, and so that whoever adds the
        // real transfer endpoint + recordTransfer method later gets a
        // clear compile-time reminder to replace this throw with the
        // real two-location submission, rather than silently falling
        // through do-nothing.
        throw StateError(
          'StockMovementSyncHandler received a "transfer" movement type '
          'for ${movement.localId} — Transfer has no backend endpoint '
          'yet (Phase 2, not built server-side today); this case exists '
          'as groundwork, not a working path.',
        );
    }

    // CORRECTED — this used to be discarded entirely: "there is nowhere
    // on-device to reconcile it TO yet." There is now.
    // ProductRepository.reconcileStockLevel exists specifically for
    // this call site. Uses movement.locationId (this device's own,
    // local-only location tag — see StockMovement's own doc comment on
    // why that's required, never sent to the backend) rather than
    // anything from the response, since the backend has no location
    // concept to report one from — this device already knows which of
    // its own locations this movement was against.
    await _productRepository.reconcileStockLevel(
      productLocalId: movement.productLocalId,
      locationId: movement.locationId,
      currentStock: response.currentStock,
    );

    await _stockMovementRepository.markSettled(localId: movement.localId);
  }
}
