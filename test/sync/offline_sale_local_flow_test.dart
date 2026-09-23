import 'dart:io';

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
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

class _MockSalesApi extends Mock implements SalesApi {}

void main() {
  late Directory tempDir;
  late File dbFile;

  const locationId = 'loc-1';
  const productId = 'prod-1';

  setUpAll(() {
    registerFallbackValue(const SaleCreateDto(
      items: [],
      amountPaid: 0,
      locationId: locationId,
    ));
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

  test('offline sale survives app restart and stays queued until Fulus Cloud is ready', () async {
    var db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final now = DateTime.now();

    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: locationId,
      name: 'Test Location',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
    ));
    await db.into(db.products).insert(ProductsCompanion.insert(
      localId: productId,
      name: 'Test Product',
      sku: 'SKU-1',
      costPrice: 100,
      sellingPrice: 150,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
    ));
    await (db.update(db.products)..where((p) => p.localId.equals(productId))).write(
      const ProductsCompanion(serverId: Value('server-product-1')),
    );
    await db.into(db.productStockLevels).insert(ProductStockLevelsCompanion.insert(
      productLocalId: productId,
      locationLocalId: locationId,
      currentStock: const Value(10),
      updatedAt: now,
      syncStatus: SyncStatus.settled,
    ));

    final repository = SaleRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: _FakeAuthRepository(),
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );

    final createdSale = await repository.createSale(SaleDraft(
      items: [SaleItem(
        localId: 'item-1',
        productLocalId: productId,
        quantity: 2,
        unitPrice: 150,
        costPriceAtSale: 100,
      )],
      locationId: locationId,
      amountPaid: 300,
    ));

    expect(await db.select(db.sales).get(), hasLength(1));
    expect(await db.select(db.syncQueueItems).get(), hasLength(1));

    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));

    final restoredSales = await db.select(db.sales).get();
    expect(restoredSales, hasLength(1));
    expect(restoredSales.single.localId, createdSale.localId);
    expect(restoredSales.single.syncStatus, SyncStatus.pending);

    final salesApi = _MockSalesApi();
    final restoredRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: _FakeAuthRepository(),
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );
    final handler = SaleSyncHandler(
      db: db,
      salesApi: salesApi,
      saleRepository: restoredRepository,
    );
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'sale': handler},
    );

    await engine.runOnce();

    verifyNever(() => salesApi.createSale(
      dto: any(named: 'dto'),
      locationLocalId: any(named: 'locationLocalId'),
    ));

    final queued = await db.select(db.syncQueueItems).get();
    expect(queued, hasLength(1));
    expect(queued.single.syncAttempts, 0);
    expect(queued.single.lastError, contains('Fulus Cloud authorization'));

    await db.close();
  });
}
