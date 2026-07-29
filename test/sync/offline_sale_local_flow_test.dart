import 'dart:io';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/sync/handlers/sale_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// ═══════════════════════════════════════════════════════════════════
/// WHAT THIS TEST IS, AND — MORE IMPORTANTLY — WHAT IT IS NOT
/// ═══════════════════════════════════════════════════════════════════
///
/// Phase 0's roadmap exit criterion (Architecture Section 14): "creates
/// a sale fully offline, kills the app, restarts it, restores
/// connectivity, and confirms exactly one sale exists server-side with
/// the correct client_reference."
///
/// Architecture Section 13 is explicit, in its own words, about what
/// satisfies that: "a real end-to-end test of the offline→sync→conflict
/// cycle using two physical or emulated devices against a real backend
/// instance — **not mocked, not simulated in a unit test**." It goes
/// further: "Nothing in this document has been run; this is the
/// concrete gate where that stops being true."
///
/// This test is exactly the kind of simulation that passage rules out
/// as sufficient. It is a real, valuable regression test of the LOCAL
/// mechanics the exit criterion depends on — genuine file-backed Drift
/// persistence (so "restart" means an actual close-and-reopen of the
/// same database file, not an in-memory instance that was never at risk
/// of losing anything), and the real SaleRepositoryImpl / SyncQueue /
/// SyncEngine / SaleSyncHandler classes wired together exactly as
/// bootstrap.dart wires them. What it does NOT do — and cannot, from
/// this environment — is touch a real backend over a real network, or
/// run on a real or emulated device. SalesApi is mocked here
/// specifically because there is no reachable backend to call.
///
/// **What still needs to happen for Phase 0 to actually be validated,
/// per Section 13's own bar:**
///   1. A real backend instance running (docker-compose.yml, this
///      repo's sibling `fulus/` checkout) with a seeded location, product,
///      and customer that have BOTH a local ULID and a matching real
///      serverId already recorded in mobile's local database — since
///      SaleSyncHandler (see its own doc comment) has no way to
///      discover a product/customer's serverId on its own yet.
///   2. The mobile app built and run against that backend
///      (--dart-define=API_BASE_URL=<the real instance>), on a real
///      device or emulator — not `flutter test`.
///   3. The manual (or scripted, via `integration_test` + a device) steps:
///      log in, create a sale with the device's radio in airplane mode,
///      force-close the app, relaunch it, disable airplane mode, and
///      confirm — by querying the real backend's own /api/sales
///      endpoint or database directly — that exactly one sale exists
///      with the client_reference matching what was created locally.
/// None of that exists yet. This test is the honest, currently-
/// achievable substitute — not a claim that the gate above is closed.
void main() {
  late Directory tempDir;
  late File dbFile;

  const locationId = 'loc-1';
  const productId = 'prod-1';

  setUpAll(() {
    // mocktail requires a registered fallback for any custom type used
    // with any()/captureAny() — this minimal instance is never actually
    // used as real data, just as a type witness. Same requirement as
    // sale_sync_handler_test.dart, whose SaleCreateDto usage this
    // mirrors.
    registerFallbackValue(const SaleCreateDto(items: [], amountPaid: 0, locationId: locationId));
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fulus_offline_sync_test_');
    dbFile = File('${tempDir.path}/test.sqlite');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'a sale created while "offline" survives an app restart (real file '
      'close/reopen) and syncs exactly once when connectivity returns',
      () async {
    // ── Phase 1: app launch #1, seed reference data ──────────────────
    // Standing in for data that would, in reality, already exist
    // locally as a result of a real (not-yet-built) product/customer
    // pull-sync — see SaleSyncHandler's own doc comment on this real,
    // named gap. Seeded with a serverId already populated specifically
    // so this test exercises the sync PATH itself, not that separate,
    // already-documented limitation.
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final now = DateTime.now();
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            localId: locationId,
            name: 'Test Location',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: productId,
            name: 'Test Product',
            sku: 'SKU-1',
            costPrice: 100,
            sellingPrice: 150,
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));

    // ── Phase 2: create a sale "while offline" ───────────────────────
    // "Offline" here means exactly what it means in the real app: the
    // write happens locally and returns without anything ever
    // attempting the network — no SyncEngine is even constructed yet
    // in this phase of the test, so there is no possible way a sync
    // attempt could happen before the restart below.
    final syncQueue1 = SyncQueue(db);
    final saleRepository1 = SaleRepositoryImpl(db: db, syncQueue: syncQueue1);

    final item = SaleItem(
      localId: 'item-1',
      productLocalId: productId,
      quantity: 2,
      unitPrice: 150,
      costPriceAtSale: 100,
    );
    final createdSale = await saleRepository1.createSale(
      SaleDraft(items: [item], locationId: locationId, amountPaid: 300),
    );

    // Confirmed BEFORE the restart: the sale exists locally and is
    // queued, nothing server-side has been attempted.
    final preRestartSales = await db.select(db.sales).get();
    expect(preRestartSales, hasLength(1));
    expect(preRestartSales.single.syncStatus, SyncStatus.pending);
    final preRestartQueue = await db.select(db.syncQueueItems).get();
    expect(preRestartQueue, hasLength(1));

    // ── Phase 3: "kill the app, restart it" ──────────────────────────
    // A genuine close of the file-backed connection, then a fresh
    // AppDatabase opened against the SAME file — this is what "restart"
    // actually means at the persistence layer, and is exactly why this
    // test uses NativeDatabase(File(...)) rather than .memory(): an
    // in-memory database would make this phase meaningless, since
    // there'd be nothing for a close to actually risk losing.
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));

    final postRestartSales = await db.select(db.sales).get();
    expect(postRestartSales, hasLength(1),
        reason: 'the sale must survive a genuine close/reopen of the '
            'same database file');
    expect(postRestartSales.single.localId, createdSale.localId);

    // ── Phase 4: "connectivity restored" — run the sync engine ───────
    // SalesApi is mocked here — see this file's own header comment on
    // exactly why, and what a real version of this test still needs.
    final mockSalesApi = _MockSalesApi();
    when(
      () => mockSalesApi.createSale(
        dto: any(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    ).thenAnswer(
      (invocation) async => Sale(
        localId: createdSale.localId,
        serverId: 'server-sale-1',
        clientReference: createdSale.clientReference,
        invoiceNumber: 'INV-001',
        locationId: locationId,
        saleDate: createdSale.saleDate,
        subtotal: createdSale.subtotal,
        discount: createdSale.discount,
        tax: createdSale.tax,
        total: createdSale.total,
        amountPaid: createdSale.amountPaid,
        items: createdSale.items,
        createdAt: createdSale.createdAt,
        updatedAt: createdSale.updatedAt,
      ),
    );

    final syncQueue2 = SyncQueue(db);
    final saleRepository2 = SaleRepositoryImpl(db: db, syncQueue: syncQueue2);
    final handler = SaleSyncHandler(
      db: db,
      salesApi: mockSalesApi,
      saleRepository: saleRepository2,
    );
    final syncEngine = SyncEngine(db: db, handlersByEntityType: {'sale': handler});

    await syncEngine.runOnce();

    // ── Phase 5: verify convergence ───────────────────────────────────
    // The strongest available check, absent a real server to query:
    // called exactly once, with the SAME client_reference the sale was
    // created with — this is the actual substance of "confirms exactly
    // one sale exists server-side with the correct client_reference,"
    // verified at the call boundary rather than by querying a live
    // backend this environment cannot reach.
    final captured = verify(
      () => mockSalesApi.createSale(
        dto: captureAny(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    ).captured;
    expect(captured, hasLength(1), reason: 'must be called exactly once');
    final dto = captured.single as SaleCreateDto;
    expect(dto.clientReference, createdSale.clientReference);
    expect(dto.items.single.productId, 'server-product-1');
    expect(dto.locationId, createdSale.locationId);

    final finalSaleRow = (await db.select(db.sales).get()).single;
    expect(finalSaleRow.syncStatus, SyncStatus.settled);
    expect(finalSaleRow.serverId, 'server-sale-1');
    expect(finalSaleRow.invoiceNumber, 'INV-001');

    expect(
      await db.select(db.syncQueueItems).get(),
      isEmpty,
      reason: 'the synced item must be removed from the queue',
    );

    await db.close();
  });
}

class _MockSalesApi extends Mock implements SalesApi {}
