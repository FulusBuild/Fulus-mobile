import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/handlers/sale_sync_handler.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSalesApi extends Mock implements SalesApi {}
class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockProductRepository extends Mock implements ProductRepository {}

class _FakeAuthRepository implements AuthRepository {
  @override
  AuthUser? get currentUser => null;
  @override
  Future<bool> hasAnyOwnerAccount() async => throw UnimplementedError();
  @override
  Future<AuthUser?> restoreSession() async => throw UnimplementedError();
  @override
  Future<AuthUser> createFirstOwner({required String fullName}) async => throw UnimplementedError();
  @override
  Future<void> setOwnLoginPin({required String pin}) async => throw UnimplementedError();
  @override
  Future<List<AuthUser>> listLocalIdentities() async => throw UnimplementedError();
  @override
  Future<AuthUser> switchLocalUser({required String userId, String? pin}) async => throw UnimplementedError();
  @override
  Future<AuthUser> createAdditionalOwner({required String fullName, required String pin}) async => throw UnimplementedError();
  @override
  Future<AuthUser> createEmployeeAccount({required String employeeId, required String pin, AuthRole role = AuthRole.employee}) async => throw UnimplementedError();
  @override
  Future<void> logout() async => throw UnimplementedError();
  @override
  Future<String?> getActiveLocationId() async => throw UnimplementedError();
  @override
  Future<void> setActiveLocationId(String locationId) async => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late MockSalesApi salesApi;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late MockProductRepository productRepository;
  late SaleRepositoryImpl saleRepository;
  late SaleSyncHandler handler;

  const locationId = 'loc-1';
  const productId = 'prod-1';
  const customerId = 'cust-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    salesApi = MockSalesApi();
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    productRepository = MockProductRepository();
    when(() => connectionState.selectedBusinessId).thenReturn(null);
    when(() => connectionState.registeredDevice).thenReturn(null);
    saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: _FakeAuthRepository(),
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );
    handler = SaleSyncHandler(
      db: db,
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
      salesApi: salesApi,
      saleRepository: saleRepository,
      productRepository: productRepository,
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
    await db.into(db.productStockLevels).insert(ProductStockLevelsCompanion.insert(
          productLocalId: productId,
          locationLocalId: locationId,
          currentStock: const Value(10),
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ));
  });

  setUpAll(() {
    registerFallbackValue(const SaleCreateDto(
      items: [],
      amountPaid: 0,
      locationId: locationId,
    ));
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

  test('pushes a Quick Sale through Fulus Cloud without a catalog product', () async {
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-1')));

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
          'data': {'entity_id': 'server-sale-quick'},
        });

    final sale = await saleRepository.createSale(
      SaleDraft(
        items: const [
          SaleItem(
            localId: 'quick-1',
            productLocalId: null,
            description: 'Phone charger',
            quantity: 1,
            unitPrice: 500,
            costPriceAtSale: 0,
          ),
        ],
        locationId: locationId,
        amountPaid: 500,
      ),
    );

    await handler.sync(queueItemFor(sale));

    final captured = verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'sale.create',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: sale.clientReference,
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    final items = captured['items'] as List;
    final item = items.single as Map<String, dynamic>;
    expect(item['product_id'], isNull);
    expect(item['description'], 'Phone charger');
    expect(item['quantity'], 1);
    expect(item['unit_price'], 500);
    expect(captured['location_id'], 'server-location-1');

    final updated = await saleRepository.getSaleByLocalId(sale.localId);
    expect(updated!.serverId, 'server-sale-quick');
  });

  test('reconciles optimistic stock when the cloud rejects a sale', () async {
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-1')));

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenThrow(
      const BusinessRuleFailure('Insufficient stock', code: 'INSUFFICIENT_STOCK'),
    );
    when(() => fulusSyncApi.fetchCanonicalEntity(
          businessId: 'business-1',
          entityType: 'product',
          entityId: 'server-product-1',
          deviceClientId: 'device-client-1',
        )).thenAnswer((_) async => FulusCanonicalEntityResponse(
          data: {
            'entity_type': 'product',
            'entity_id': 'server-product-1',
            'operation': 'upsert',
            'product': {
              'id': 'server-product-1',
              'name': 'Test Product',
              'sku': 'SKU-1',
              'barcode': null,
              'category_id': null,
              'supplier_id': null,
              'cost_price': 100,
              'selling_price': 150,
              'low_stock_threshold': 5,
              'is_active': true,
              'updated_at': '2026-09-23T10:00:00Z',
              'deleted_at': null,
            },
            'stock_levels': [
              {
                'location_id': 'server-location-1',
                'current_stock': 3,
                'updated_at': '2026-09-23T10:00:00Z',
              },
            ],
          },
        ));
    when(() => productRepository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          sku: any(named: 'sku'),
          barcode: any(named: 'barcode'),
          categoryId: any(named: 'categoryId'),
          supplierId: any(named: 'supplierId'),
          costPrice: any(named: 'costPrice'),
          sellingPrice: any(named: 'sellingPrice'),
          lowStockThreshold: any(named: 'lowStockThreshold'),
          isActive: any(named: 'isActive'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
          stockLevels: any(named: 'stockLevels'),
        )).thenAnswer((_) async {});

    final sale = await createLocalSale();

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(
        isA<BusinessRuleFailure>().having(
          (failure) => failure.code,
          'code',
          'INSUFFICIENT_STOCK',
        ),
      ),
    );

    final localStock = await (db.select(db.productStockLevels)
          ..where((s) =>
              s.productLocalId.equals(productId) &
              s.locationLocalId.equals(locationId)))
        .getSingle();
    expect(localStock.currentStock, 3);
    verify(() => productRepository.reconcileServerState(
          serverId: 'server-product-1',
          name: 'Test Product',
          sku: 'SKU-1',
          barcode: null,
          categoryId: null,
          supplierId: null,
          costPrice: 100,
          sellingPrice: 150,
          lowStockThreshold: 5,
          isActive: true,
          updatedAt: DateTime.parse('2026-09-23T10:00:00Z'),
          deletedAt: null,
          stockLevels: any(named: 'stockLevels'),
        )).called(1);
  });

  test('never falls back to the legacy Sales API when Fulus Cloud is unavailable', () async {
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));

    final sale = await createLocalSale();

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(
        isA<SyncFailure>().having(
          (failure) => failure.kind,
          'kind',
          SyncErrorKind.dependencyNotReady,
        ),
      ),
    );

    verifyNever(() => salesApi.createSale(
          dto: any(named: 'dto'),
          locationLocalId: any(named: 'locationLocalId'),
        ));
  });

  test('reports cloud readiness before attempting a sale whose product is not cloud-ready', () async {
    final sale = await createLocalSale();

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(
        isA<SyncFailure>().having(
          (failure) => failure.kind,
          'kind',
          SyncErrorKind.dependencyNotReady,
        ),
      ),
    );

    verifyNever(() => salesApi.createSale(
          dto: any(named: 'dto'),
          locationLocalId: any(named: 'locationLocalId'),
        ));
  });

  test('reports the missing customer serverId before attempting the API', () async {
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
        );

    final sale = await createLocalSale(withCustomerId: customerId);

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Customer $customerId has no serverId yet.'),
        ),
      ),
    );

    verifyNever(() => salesApi.createSale(
          dto: any(named: 'dto'),
          locationLocalId: any(named: 'locationLocalId'),
        ));
  });

  test('throws for an operation other than create', () async {
    final sale = await createLocalSale();

    await expectLater(
      handler.sync(queueItemFor(sale, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });
}
