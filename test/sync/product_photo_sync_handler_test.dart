import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/product_image_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/sync/handlers/product_photo_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:mocktail/mocktail.dart';

class MockProductImageApi extends Mock implements ProductImageApi {}

class MockProductRepository extends Mock implements ProductRepository {}

class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  const cloudUrl =
      'https://example.supabase.co/storage/v1/object/public/product-images/business-1/p1/1.jpg';

  late AppDatabase db;
  late MockProductImageApi imageApi;
  late MockProductRepository repository;
  late MockFulusConnectionState connection;
  late ProductPhotoSyncHandler handler;
  late File photo;

  setUpAll(() {
    registerFallbackValue(File('fallback.jpg'));
  });

  Future<void> seed({String? photoPath, String? serverId, DateTime? deletedAt}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          localId: 'p1',
          serverId: serverId == null ? const Value.absent() : Value(serverId),
          name: 'Product',
          sku: 'SKU-1',
          costPrice: 10,
          sellingPrice: 20,
          photoPath: Value(photoPath),
          deletedAt: Value(deletedAt),
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
          syncStatus: SyncStatus.pending,
        ));
  }

  Future<SyncQueueItem> queueItem() async {
    await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
          id: 'photo-task',
          entityType: 'product_photo',
          entityLocalId: 'p1',
          operation: 'upload',
          priority: 2,
          enqueuedAt: DateTime(2026, 10, 1),
        ));
    return db.select(db.syncQueueItems).getSingle();
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    imageApi = MockProductImageApi();
    repository = MockProductRepository();
    connection = MockFulusConnectionState();
    handler = ProductPhotoSyncHandler(
      db: db,
      productRepository: repository,
      fulusConnectionState: connection,
      productImageApi: imageApi,
    );
    when(() => connection.selectedBusinessId).thenReturn('business-1');
    when(() => connection.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
    when(() => repository.updateProduct(
          localId: any(named: 'localId'),
          photoPath: any(named: 'photoPath'),
        )).thenAnswer((_) async {});
    when(() => repository.setLocalOverrides(
          productLocalId: any(named: 'productLocalId'),
          photoPath: any(named: 'photoPath'),
          clearPhoto: any(named: 'clearPhoto'),
        )).thenAnswer((_) async {});

    photo = File('${Directory.systemTemp.path}/fulus-photo-handler-${DateTime.now().microsecondsSinceEpoch}.jpg');
    await photo.writeAsBytes(<int>[1, 2, 3]);
  });

  tearDown(() async {
    if (await photo.exists()) await photo.delete();
    await db.close();
  });

  test('uploads the local photo, then queues a product update with the cloud URL', () async {
    await seed(photoPath: photo.path, serverId: 'server-1');
    when(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        )).thenAnswer((_) async => cloudUrl);

    await handler.sync(await queueItem());

    verify(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: 'business-1',
          productLocalId: 'p1',
        )).called(1);
    verify(() => repository.updateProduct(localId: 'p1', photoPath: cloudUrl)).called(1);
  });

  test('waits for the product create when there is no server identity yet', () async {
    await seed(photoPath: photo.path);
    final item = await queueItem();

    await expectLater(
      handler.sync(item),
      throwsA(isA<SyncFailure>().having((f) => f.kind, 'kind', SyncErrorKind.dependencyNotReady)),
    );
    verifyNever(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        ));
  });

  test('drops a dead local reference instead of retrying forever', () async {
    await seed(photoPath: '/definitely/not/here.jpg', serverId: 'server-1');

    await handler.sync(await queueItem());

    verify(() => repository.setLocalOverrides(productLocalId: 'p1', clearPhoto: true)).called(1);
    verifyNever(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        ));
  });

  test('does nothing when the photo is already a cloud URL', () async {
    await seed(photoPath: cloudUrl, serverId: 'server-1');

    await handler.sync(await queueItem());

    verifyNever(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        ));
    verifyNever(() => repository.updateProduct(
          localId: any(named: 'localId'),
          photoPath: any(named: 'photoPath'),
        ));
  });

  test('discards the upload result when the photo changed during the upload', () async {
    await seed(photoPath: photo.path, serverId: 'server-1');
    when(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        )).thenAnswer((_) async {
      await (db.update(db.products)..where((p) => p.localId.equals('p1')))
          .write(const ProductsCompanion(photoPath: Value('/data/photos/newer.jpg')));
      return cloudUrl;
    });

    await handler.sync(await queueItem());

    verifyNever(() => repository.updateProduct(
          localId: any(named: 'localId'),
          photoPath: any(named: 'photoPath'),
        ));
    verify(() => repository.setLocalOverrides(
          productLocalId: 'p1',
          photoPath: '/data/photos/newer.jpg',
        )).called(1);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });

  test('a rejected upload surfaces its typed failure for the engine to classify', () async {
    await seed(photoPath: photo.path, serverId: 'server-1');
    when(() => imageApi.upload(
          file: any(named: 'file'),
          businessId: any(named: 'businessId'),
          productLocalId: any(named: 'productLocalId'),
        )).thenThrow(const SyncFailure(
      kind: SyncErrorKind.validation,
      message: 'too large',
    ));

    await expectLater(
      handler.sync(await queueItem()),
      throwsA(isA<SyncFailure>().having((f) => f.shouldRetry, 'shouldRetry', isFalse)),
    );
  });
}

