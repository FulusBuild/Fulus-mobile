import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/product_repository_impl.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

void main() {
  late AppDatabase db;
  late ProductRepositoryImpl repository;

  const cloudUrl =
      'https://example.supabase.co/storage/v1/object/public/product-images/b/p1/1.jpg';

  Future<void> seedProduct({String? photoPath, String? serverId}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          localId: 'p1',
          locationId: const Value('loc-1'),
          serverId: serverId == null ? const Value.absent() : Value(serverId),
          name: 'Product p1',
          sku: 'SKU-p1',
          costPrice: 500,
          sellingPrice: 1000,
          photoPath: Value(photoPath),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  }

  Future<ProductRow> product() =>
      (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();

  Future<List<SyncQueueItem>> queue() => db.select(db.syncQueueItems).get();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'loc-1', name: 'Main Store',
      createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));
    repository = ProductRepositoryImpl(db: db, syncQueue: SyncQueue(db));
  });

  tearDown(() async => db.close());

  test('a device-local photo queues exactly one upload task', () async {
    await seedProduct();
    await repository.setLocalOverrides(
      productLocalId: 'p1',
      photoPath: '/data/photos/a.jpg',
    );
    await repository.setLocalOverrides(
      productLocalId: 'p1',
      photoPath: '/data/photos/a.jpg',
    );

    final photoTasks = (await queue()).where((q) => q.entityType == 'product_photo');
    expect(photoTasks, hasLength(1));
    expect(photoTasks.single.entityLocalId, 'p1');
    expect(photoTasks.single.operation, 'upload');
    expect(photoTasks.single.priority, SyncPriority.photosAndBulkImport);
  });

  test('a cloud photo URL needs no upload task', () async {
    await seedProduct();
    await repository.setLocalOverrides(productLocalId: 'p1', photoPath: cloudUrl);

    expect(await queue(), isEmpty);
    expect((await product()).photoPath, cloudUrl);
  });

  test('clearPhoto removes the photo, queues an update and cancels a pending upload', () async {
    await seedProduct(serverId: 'server-1');
    await repository.updateProduct(localId: 'p1', photoPath: '/data/photos/a.jpg');
    expect((await queue()).map((q) => q.entityType), contains('product_photo'));

    await repository.updateProduct(localId: 'p1', clearPhoto: true);

    final row = await product();
    expect(row.photoPath, isNull);
    expect(row.syncStatus, SyncStatus.pending);
    final items = await queue();
    expect(items.where((q) => q.entityType == 'product_photo'), isEmpty);
    expect(items.where((q) => q.entityType == 'product' && q.operation == 'update'), hasLength(1));
  });

  test('setLocalOverrides clearPhoto queues a cloud update and cancels photo upload', () async {
    await seedProduct(photoPath: cloudUrl, serverId: 'server-1');
    await repository.setLocalOverrides(productLocalId: 'p1', clearPhoto: true);

    expect((await product()).photoPath, isNull);
    final items = await queue();
    expect(items.where((q) => q.entityType == 'product_photo'), isEmpty);
    expect(items.where((q) => q.entityType == 'product' && q.operation == 'update'), hasLength(1));
  });

  test('a null photoPath still means "leave the photo unchanged"', () async {
    await seedProduct(photoPath: cloudUrl, serverId: 'server-1');
    await repository.updateProduct(localId: 'p1', name: 'Renamed');

    expect((await product()).photoPath, cloudUrl);
  });

  test('a pull does not erase a photo that has not uploaded yet', () async {
    await seedProduct(photoPath: '/data/photos/a.jpg', serverId: 'server-1');

    await repository.reconcileServerState(
      serverId: 'server-1',
      name: 'Product p1',
      sku: 'SKU-p1',
      costPrice: 500,
      sellingPrice: 1000,
      lowStockThreshold: 0,
      isActive: true,
      photoPath: null,
      updatedAt: DateTime(2026, 2, 1),
      stockLevels: const [],
    );

    expect((await product()).photoPath, '/data/photos/a.jpg');
  });

  test('a pull still applies the server photo when the local one is already a URL', () async {
    await seedProduct(photoPath: cloudUrl, serverId: 'server-1');
    const newer =
        'https://example.supabase.co/storage/v1/object/public/product-images/b/p1/2.jpg';

    await repository.reconcileServerState(
      serverId: 'server-1',
      name: 'Product p1',
      sku: 'SKU-p1',
      costPrice: 500,
      sellingPrice: 1000,
      lowStockThreshold: 0,
      isActive: true,
      photoPath: newer,
      updatedAt: DateTime(2026, 2, 1),
      stockLevels: const [],
    );

    expect((await product()).photoPath, newer);
  });
}

