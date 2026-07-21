import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/local/database/tables.dart';
import 'package:bms_mobile/data/remote/endpoints/sales_api.dart';
import 'package:bms_mobile/data/repositories/sale_repository_impl.dart';
import 'package:bms_mobile/domain/entities/sale.dart';
import 'package:bms_mobile/domain/entities/sale_draft.dart';
import 'package:bms_mobile/sync/handlers/sale_sync_handler.dart';
import 'package:bms_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSalesApi extends Mock implements SalesApi {}

void main() {
  late AppDatabase db;
  late MockSalesApi salesApi;
  late SaleRepositoryImpl saleRepository;
  late SaleSyncHandler handler;

  const locationId = 'loc-1';
  const productId = 'prod-1';
  const customerId = 'cust-1';

  setUpAll(() {
    // mocktail requires a registered fallback for any custom type used
    // with any()/captureAny() — this minimal instance is never actually
    // used as real data, just as a type witness.
    registerFallbackValue(const SaleCreateDto(items: [], amountPaid: 0));
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    salesApi = MockSalesApi();
    saleRepository = SaleRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = SaleSyncHandler(
      db: db,
      salesApi: salesApi,
      saleRepository: saleRepository,
    );

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
    // Deliberately NO serverId on this product — several tests below
    // rely on that being the starting state; the one test that needs a
    // synced product sets serverId explicitly first.
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
  });

  tearDown(() async {
    await db.close();
  });

  Future<Sale> createLocalSale({String? withCustomerId}) {
    final item = SaleItem(
      localId: 'item-1',
      productLocalId: productId,
      quantity: 2,
      unitPrice: 150,
      costPriceAtSale: 100,
    );
    final draft = SaleDraft(
      items: [item],
      locationId: locationId,
      amountPaid: 300,
      customerId: withCustomerId,
    );
    return saleRepository.createSale(draft);
  }

  /// handler.sync only reads item.operation and item.entityLocalId — a
  /// minimal row built directly is enough; the queue plumbing itself is
  /// already covered in sync_engine_test.dart, not what these tests
  /// are about.
  SyncQueueItem queueItemFor(Sale sale, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'sale',
      entityLocalId: sale.localId,
      operation: operation,
      priority: 0,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  test(
      'sends the product\'s serverId (not its local id) and marks the '
      'local sale synced from the response', () async {
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));

    final sale = await createLocalSale();

    when(
      () => salesApi.createSale(
        dto: any(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    ).thenAnswer(
      (_) async => Sale(
        localId: sale.localId,
        serverId: 'server-sale-1',
        clientReference: sale.localId,
        invoiceNumber: 'INV-001',
        locationId: locationId,
        saleDate: sale.saleDate,
        subtotal: sale.subtotal,
        discount: sale.discount,
        tax: sale.tax,
        total: sale.total,
        amountPaid: sale.amountPaid,
        items: sale.items,
        createdAt: sale.createdAt,
        updatedAt: sale.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(sale));

    final captured = verify(
      () => salesApi.createSale(
        dto: captureAny(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    ).captured;
    final dto = captured.single as SaleCreateDto;
    expect(dto.items.single.productId, 'server-product-1');
    expect(dto.clientReference, sale.localId);

    final updated = await saleRepository.getSaleByLocalId(sale.localId);
    expect(updated!.serverId, 'server-sale-1');
    expect(updated.invoiceNumber, 'INV-001');
  });

  test('throws before calling the API when the product has no serverId yet',
      () async {
    final sale = await createLocalSale(); // product left unsynced in setUp

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(isA<StateError>()),
    );

    verifyNever(
      () => salesApi.createSale(
        dto: any(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    );
  });

  test(
      'throws before calling the API when the sale has a customer with no '
      'serverId yet', () async {
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));

    final now = DateTime.now();
    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            localId: customerId,
            name: 'Test Customer',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        ); // no serverId

    final sale = await createLocalSale(withCustomerId: customerId);

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(isA<StateError>()),
    );

    verifyNever(
      () => salesApi.createSale(
        dto: any(named: 'dto'),
        locationLocalId: any(named: 'locationLocalId'),
      ),
    );
  });

  test('throws for an operation other than create', () async {
    final sale = await createLocalSale();

    await expectLater(
      handler.sync(queueItemFor(sale, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });
}
