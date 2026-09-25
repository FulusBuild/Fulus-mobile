import 'dart:async';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/handlers/sale_sync_handler.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSalesApi extends Mock implements SalesApi {}
class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockProductRepository extends Mock implements ProductRepository {}
class MockCustomerRepository extends Mock implements CustomerRepository {}

class _FakeAuthRepository implements AuthRepository {
  String? activeLocationId;

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
  Future<String?> getActiveLocationId() async => activeLocationId;
  @override
  Future<void> setActiveLocationId(String locationId) async {
    activeLocationId = locationId;
  }
}

void main() {
  late AppDatabase db;
  late MockSalesApi salesApi;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late MockProductRepository productRepository;
  late MockCustomerRepository customerRepository;
  late SaleRepositoryImpl saleRepository;
  late SaleSyncHandler handler;
  late SyncExecutionLease executionLease;
  late _FakeAuthRepository authRepository;

  const locationId = 'loc-1';
  const productId = 'prod-1';
  const customerId = 'cust-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    executionLease = SyncExecutionLease(db);
    salesApi = MockSalesApi();
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    authRepository = _FakeAuthRepository();
    productRepository = MockProductRepository();
    customerRepository = MockCustomerRepository();
    when(() => connectionState.selectedBusinessId).thenReturn(null);
    when(() => connectionState.registeredDevice).thenReturn(null);
    saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: authRepository,
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );
    handler = SaleSyncHandler(
      db: db,
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
      salesApi: salesApi,
      saleRepository: saleRepository,
      productRepository: productRepository,
      customerRepository: customerRepository,
      executionLease: executionLease,
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
    await executionLease.release();
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

  test('submits a pending sale with its original location after active location switches', () async {
    final now = DateTime.now();
    await db.into(db.locations).insert(
      LocationsCompanion.insert(
        localId: 'loc-2',
        name: 'Location B',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
      ),
    );
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-A')));
    await (db.update(db.locations)..where((l) => l.localId.equals('loc-2')))
        .write(const LocationsCompanion(serverId: Value('server-location-B')));

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
          'data': {'entity_id': 'server-sale-A'},
        });

    final sale = await createLocalSale();
    await authRepository.setActiveLocationId('loc-2');

    expect(await authRepository.getActiveLocationId(), 'loc-2');
    expect(sale.locationId, locationId);

    await handler.sync(queueItemFor(sale));

    final captured = verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'sale.create',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: sale.clientReference,
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    expect(captured['location_id'], 'server-location-A');
    expect(captured['location_id'], isNot('server-location-B'));
  });

  test('keeps the original location while a sale sync is in flight during an active-location switch', () async {
    final now = DateTime.now();
    await db.into(db.locations).insert(
      LocationsCompanion.insert(
        localId: 'loc-2',
        name: 'Location B',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
      ),
    );
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-A')));
    await (db.update(db.locations)..where((l) => l.localId.equals('loc-2')))
        .write(const LocationsCompanion(serverId: Value('server-location-B')));

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));

    final submitCompleter = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> submittedPayload;
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) {
      submittedPayload =
          Map<String, dynamic>.from(invocation.namedArguments[#payload] as Map);
      return submitCompleter.future;
    });

    final sale = await createLocalSale();
    await authRepository.setActiveLocationId(locationId);

    final syncFuture = handler.sync(queueItemFor(sale));
    await Future<void>.delayed(Duration.zero);

    await authRepository.setActiveLocationId('loc-2');
    expect(await authRepository.getActiveLocationId(), 'loc-2');
    expect(submittedPayload['location_id'], 'server-location-A');
    expect(submittedPayload['location_id'], isNot('server-location-B'));

    submitCompleter.complete({
      'data': {'entity_id': 'server-sale-A'},
    });
    await syncFuture;

    final stored = await saleRepository.getSaleByLocalId(sale.localId);
    expect(stored!.locationId, locationId);
    expect(stored.serverId, 'server-sale-A');
  });

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
    expect(await executionLease.acquire(), isTrue);

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

    // ProductRepository is mocked in this handler test, so the canonical
    // reconciler call is verified below rather than mutating SQLite here.
    // The sale itself optimistically decremented 10 -> 8 before the cloud
    // rejection; a real ProductRepository applies the canonical 3 there.
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

  test('does not apply rejected-sale canonical stock over a newer product mutation', () async {
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
        )).thenAnswer((_) async {
      await db.into(db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: 'newer-product-mutation',
          entityType: 'product',
          entityLocalId: productId,
          operation: 'update',
          priority: 0,
          enqueuedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );
      return FulusCanonicalEntityResponse(
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
      );
    });

    final sale = await createLocalSale();
    expect(await executionLease.acquire(), isTrue);

    await expectLater(
      handler.sync(queueItemFor(sale)),
      throwsA(isA<BusinessRuleFailure>()),
    );

    verifyNever(() => productRepository.reconcileServerState(
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
        ));
  });



  test('does not apply rejected sale product canonical over a newer stock movement', () async {
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
      const BusinessRuleFailure('Rejected sale', code: 'SALE_REJECTED'),
    );
    when(() => fulusSyncApi.fetchCanonicalEntity(
          businessId: 'business-1',
          entityType: 'product',
          entityId: 'server-product-1',
          deviceClientId: 'device-client-1',
        )).thenAnswer((_) async {
      final now = DateTime.now();
      await db.into(db.stockMovements).insert(
        StockMovementsCompanion.insert(
          localId: 'movement-1',
          productLocalId: productId,
          locationId: locationId,
          movementType: 'out',
          quantity: const Value(1),
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        ),
      );
      await db.into(db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: 'newer-stock-movement',
          entityType: 'stock_movement',
          entityLocalId: 'movement-1',
          operation: 'create',
          priority: 0,
          enqueuedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );
      return FulusCanonicalEntityResponse(data: {
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
      });
    });
    final sale = await createLocalSale();
    expect(await executionLease.acquire(), isTrue);

    await expectLater(handler.sync(queueItemFor(sale)), throwsA(isA<BusinessRuleFailure>()));

    verifyNever(() => productRepository.reconcileServerState(
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
        ));
  });

  test('does not apply rejected sale customer canonical over a newer repayment', () async {
    await (db.update(db.products)..where((p) => p.localId.equals(productId)))
        .write(const ProductsCompanion(serverId: Value('server-product-1')));
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-1')));
    final now = DateTime.now();
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        localId: customerId,
        serverId: const Value('server-customer-1'),
        name: 'Test Customer',
        outstandingBalance: const Value(100),
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
      ),
    );
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
      const BusinessRuleFailure('Rejected sale', code: 'SALE_REJECTED'),
    );
    when(() => fulusSyncApi.fetchCanonicalEntity(
          businessId: 'business-1',
          entityType: 'customer',
          entityId: 'server-customer-1',
          deviceClientId: 'device-client-1',
        )).thenAnswer((_) async {
      await db.into(db.syncQueueItems).insert(
        SyncQueueItemsCompanion.insert(
          id: 'newer-repayment',
          entityType: 'customer_ledger',
          entityLocalId: 'repayment-1',
          operation: 'repayment',
          priority: 0,
          enqueuedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );
      await db.into(db.customerLedgerEntries).insert(
        CustomerLedgerEntriesCompanion.insert(
          localId: 'repayment-1',
          customerLocalId: customerId,
          entryType: 'repayment',
          amount: 50,
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        ),
      );
      return FulusCanonicalEntityResponse(data: {
        'entity_type': 'customer',
        'entity_id': 'server-customer-1',
        'operation': 'upsert',
        'row': {
          'id': 'server-customer-1',
          'name': 'Test Customer',
          'phone': null,
          'email': null,
          'address': null,
          'notes': null,
          'outstanding_balance': 0,
          'duplicate_warning': null,
          'updated_at': '2026-09-23T10:00:00Z',
          'is_active': true,
        },
      });
    });
    final sale = await createLocalSale(withCustomerId: customerId);
    expect(await executionLease.acquire(), isTrue);

    await expectLater(handler.sync(queueItemFor(sale)), throwsA(isA<BusinessRuleFailure>()));

    verifyNever(() => customerRepository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          address: any(named: 'address'),
          notes: any(named: 'notes'),
          outstandingBalance: any(named: 'outstandingBalance'),
          duplicateWarning: any(named: 'duplicateWarning'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
        ));
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
