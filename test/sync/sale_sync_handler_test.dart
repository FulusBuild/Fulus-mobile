import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/sales_api.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/handlers/sale_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSalesApi extends Mock implements SalesApi {}

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
  late SaleRepositoryImpl saleRepository;
  late SaleSyncHandler handler;

  const locationId = 'loc-1';
  const productId = 'prod-1';
  const customerId = 'cust-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    salesApi = MockSalesApi();
    saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: _FakeAuthRepository(),
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );
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
