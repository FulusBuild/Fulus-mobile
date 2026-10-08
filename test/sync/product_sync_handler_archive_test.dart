import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/product_image_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/sync/handlers/product_sync_handler.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockProductImageApi extends Mock implements ProductImageApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(File('fulus-test-product-image.jpg'));
  });
  late AppDatabase db;
  late MockFulusSyncApi api;
  late MockFulusConnectionState connectionState;
  late MockProductRepository productRepository;
  late ProductSyncHandler handler;
  late MockProductImageApi productImageApi;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    productRepository = MockProductRepository();
    productImageApi = MockProductImageApi();
    handler = ProductSyncHandler(
      productRepository: productRepository,
      db: db,
      fulusSyncApi: api,
      fulusConnectionState: connectionState,
      productImageApi: productImageApi,
    );

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
    when(() => productRepository.markSynced(
          localId: any(named: 'localId'),
          serverId: any(named: 'serverId'),
          operationId: any(named: 'operationId'),
        )).thenAnswer((_) async {});
    when(() => productRepository.setLocalOverrides(
          productLocalId: any(named: 'productLocalId'),
          photoPath: any(named: 'photoPath'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async => db.close());

  test('serializes local minor-unit product prices as major-unit cloud values', () async {
    final now = DateTime(2026, 10, 5);
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'p-money-boundary',
        name: 'Money boundary',
        sku: 'MONEY-BOUNDARY-1',
        costPrice: 12500,
        sellingPrice: 30000,
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'queue-money-boundary',
        entityType: 'product',
        entityLocalId: 'p-money-boundary',
        operation: 'create',
        priority: 0,
        enqueuedAt: now,
      ),
    );
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
      'data': {'entity_id': 'server-money-boundary'},
    });

    await handler.sync(await db.select(db.syncQueueItems).getSingle());

    final captured = verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.create',
          operationId: 'queue-money-boundary',
          deviceClientId: 'device-client-1',
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    expect(captured['cost_price'], '125.00');
    expect(captured['selling_price'], '300.00');
  });

  test('creates then archives a pre-sync product without reusing the stale create cursor', () async {
    final now = DateTime(2026, 9, 22);
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'p-pre-sync',
        name: 'Archived before cloud',
        sku: 'ARCHIVE-PRE-1',
        costPrice: 10,
        sellingPrice: 20,
        isActive: const Value(false),
        deletedAt: Value(now),
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'queue-product-create',
        entityType: 'product',
        entityLocalId: 'p-pre-sync',
        operation: 'create',
        priority: 0,
        enqueuedAt: now,
        baseCursor: const Value(10),
      ),
    );

    var call = 0;
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      call++;
      if (call == 1) {
        return {
          'data': {'entity_id': 'server-pre-sync', 'sync_sequence': 11},
        };
      }
      return {
        'data': {'entity_id': 'server-pre-sync', 'status': 'deleted'},
      };
    });

    final item = await db.select(db.syncQueueItems).getSingle();
    await handler.sync(item);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.create',
          operationId: 'queue-product-create',
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);
    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.delete',
          operationId: 'queue-product-create:delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-pre-sync',
            'base_cursor': 11,
          },
        )).called(1);
  });

  test('uploads a local product image before create sync and persists its cloud URL', () async {
    final now = DateTime(2026, 9, 28);
    final image = File(
      '${Directory.systemTemp.path}/fulus-product-image-${now.microsecondsSinceEpoch}.jpg',
    );
    await image.writeAsBytes(<int>[1, 2, 3, 4]);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'p-image-create',
        name: 'Product with image',
        sku: 'IMAGE-1',
        costPrice: 10,
        sellingPrice: 20,
        photoPath: Value(image.path),
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'queue-product-image-create',
        entityType: 'product',
        entityLocalId: 'p-image-create',
        operation: 'create',
        priority: 0,
        enqueuedAt: now,
      ),
    );

    when(() => productImageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        )).thenAnswer(
      (_) async => 'https://example.supabase.co/storage/v1/object/public/product-images/business-1/p-image-create/image.jpg',
    );
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer(
      (_) async => {
        'data': {
          'entity_id': 'server-image-product',
          'sync_sequence': 21,
        },
      },
    );

    final item = await db.select(db.syncQueueItems).getSingle();
    await handler.sync(item);

    verify(() => productImageApi.upload(
          file: any(named: 'file'),
          businessId: 'business-1',
          productLocalId: 'p-image-create',
        )).called(1);

    final operation = verify(() => api.submitOperation(
      businessId: 'business-1',
      operationType: 'product.create',
      operationId: 'queue-product-image-create',
      deviceClientId: 'device-client-1',
      payload: captureAny(named: 'payload'),
    )).captured.single as Map<String, dynamic>;
    expect(
      operation['photo_path'],
      'https://example.supabase.co/storage/v1/object/public/product-images/business-1/p-image-create/image.jpg',
    );
  });

  test('product create proceeds when photo upload fails and retries photo separately', () async {
    final now = DateTime(2026, 10, 1);
    await db.into(db.locations).insert(
      LocationsCompanion.insert(
        localId: 'location-photo-failure',
        serverId: const Value('server-location-photo-failure'),
        name: 'Main',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'p-image-failure',
        name: 'Product with local image',
        sku: 'IMAGE-FAIL-1',
        costPrice: 10000,
        sellingPrice: 15000,
        photoPath: const Value('/tmp/fulus-product-image.jpg'),
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );
    await db.into(db.productStockLevels).insert(
      ProductStockLevelsCompanion.insert(
        productLocalId: 'p-image-failure',
        locationLocalId: 'location-photo-failure',
        currentStock: const Value(12),
        updatedAt: now,
        syncStatus: SyncStatus.settled,
      ),
    );
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'queue-product-image-failure',
        entityType: 'product',
        entityLocalId: 'p-image-failure',
        operation: 'create',
        priority: 0,
        enqueuedAt: now,
      ),
    );

    final request = RequestOptions(path: '/storage/v1/object/product-images');
    when(() => productImageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        )).thenThrow(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 400,
          data: {'message': 'Storage rejected image upload'},
        ),
      ),
    );
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
      'data': {'entity_id': 'server-image-failure-product', 'sync_sequence': 22},
    });
    when(() => productRepository.updateProduct(
          localId: any(named: 'localId'),
          photoPath: any(named: 'photoPath'),
        )).thenAnswer((_) async {});

    await handler.sync(await db.select(db.syncQueueItems).getSingle());

    final payload = verify(() => api.submitOperation(
      businessId: 'business-1',
      operationType: 'product.create',
      operationId: 'queue-product-image-failure',
      deviceClientId: 'device-client-1',
      payload: captureAny(named: 'payload'),
    )).captured.single as Map<String, dynamic>;
    expect(payload['initial_stock'], 12);
    expect(payload['location_id'], 'server-location-photo-failure');
    expect(payload.containsKey('photo_path'), isFalse);
    verify(() => productRepository.markSynced(
      localId: 'p-image-failure',
      serverId: 'server-image-failure-product',
      operationId: 'queue-product-image-failure',
    )).called(1);
    verify(() => productRepository.updateProduct(
      localId: 'p-image-failure',
      photoPath: '/tmp/fulus-product-image.jpg',
    )).called(1);
  });

  test('archives an already-synced product through catalog.delete', () async {
    final now = DateTime(2026, 9, 22);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: 'p1',
            serverId: const Value('server-product-1'),
            name: 'Archived product',
            sku: 'ARCHIVE-1',
            costPrice: 10,
            sellingPrice: 20,
            isActive: const Value(false),
            deletedAt: Value(now),
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          ),
        );

    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: 'queue-product-delete',
            entityType: 'product',
            entityLocalId: 'p1',
            operation: 'update',
            priority: 0,
            enqueuedAt: now,
          ),
        );

    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer(
      (_) async => {
        'data': {
          'entity_id': 'server-product-1',
          'status': 'deleted',
        },
      },
    );

    final item = await db.select(db.syncQueueItems).getSingle();
    await handler.sync(item);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.delete',
          operationId: 'queue-product-delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-product-1',
          },
        )).called(1);
    verify(() => productRepository.markSynced(
          localId: 'p1',
          serverId: 'server-product-1',
          operationId: 'queue-product-delete',
        )).called(1);
  });
}
