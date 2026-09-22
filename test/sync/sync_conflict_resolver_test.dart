import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide isNotNull, isNull;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_canonical_reconciler_typed.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/sync/sync_conflict_resolver.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi api;
  late MockFulusConnectionState connectionState;
  late CustomerRepositoryImpl customers;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    customers = CustomerRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
    );
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.isDeviceAuthorized).thenReturn(true);
    when(() => connectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
  });

  tearDown(() async => db.close());

  test('reconciles authoritative state before clearing a parked conflict', () async {
    final customer = await customers.createCustomer(
      const CustomerDraft(
        name: 'Customer',
        phone: '+2348000000000',
      ),
    );
    await customers.markSynced(
      localId: customer.localId,
      serverId: 'server-customer-1',
    );
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.entityLocalId.equals(customer.localId)))
        .go();

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'operation-1',
        entityType: 'customer',
        entityLocalId: customer.localId,
        operation: 'update',
        priority: 1,
        enqueuedAt: DateTime.utc(2026, 9, 21),
      ),
    );
    await db.into(db.syncConflictRecords).insert(
      SyncConflictRecordsCompanion.insert(
        id: 'operation-1:conflict',
        operationId: 'operation-1',
        entityType: 'customer',
        entityLocalId: customer.localId,
        code: const Value('SYNC_CONFLICT'),
        message: 'Customer changed on another device.',
        createdAt: DateTime.utc(2026, 9, 21),
      ),
    );

    var reconciled = false;
    final reconciler = FulusCanonicalTypedReconciler(
      api: api,
      handlers: {
        'customer': (response) async {
          reconciled = true;
          expect(response.entityId, 'server-customer-1');
        },
      },
    );
    when(() => api.fetchCanonicalEntity(
          businessId: 'business-1',
          entityType: 'customer',
          entityId: 'server-customer-1',
          deviceClientId: 'device-client-1',
        )).thenAnswer(
      (_) async => FulusCanonicalEntityResponse(
        data: {
          'entity_type': 'customer',
          'entity_id': 'server-customer-1',
          'operation': 'upsert',
          'row': {'id': 'server-customer-1'},
        },
      ),
    );

    final resolver = SyncConflictResolver(
      db: db,
      reconciler: reconciler,
      connectionState: connectionState,
      preferences: preferences,
    );

    await resolver.keepCloudVersion('operation-1:conflict');

    expect(reconciled, isTrue);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
    final conflict =
        await (db.select(db.syncConflictRecords)
              ..where((c) => c.id.equals('operation-1:conflict')))
            .getSingle();
    expect(conflict.resolvedAt != null, isTrue);
    expect(conflict.resolution, 'kept_authoritative_cloud_version');
  });

  test('rebases a local conflict and leaves it unresolved until push succeeds', () async {
    final customer = await customers.createCustomer(
      const CustomerDraft(name: 'Local Customer'),
    );
    await customers.markSynced(
      localId: customer.localId,
      serverId: 'server-customer-2',
    );
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.entityLocalId.equals(customer.localId)))
        .go();

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'operation-2',
        entityType: 'customer',
        entityLocalId: customer.localId,
        operation: 'update',
        priority: 1,
        enqueuedAt: DateTime.utc(2026, 9, 21),
        baseCursor: const Value(4),
        syncAttempts: const Value(5),
        lastError: const Value('SYNC_CONFLICT'),
      ),
    );
    await db.into(db.syncConflictRecords).insert(
      SyncConflictRecordsCompanion.insert(
        id: 'operation-2:conflict',
        operationId: 'operation-2',
        entityType: 'customer',
        entityLocalId: customer.localId,
        code: const Value('SYNC_CONFLICT'),
        message: 'Customer changed on another device.',
        createdAt: DateTime.utc(2026, 9, 21),
      ),
    );

    final resolver = SyncConflictResolver(
      db: db,
      reconciler: FulusCanonicalTypedReconciler(api: api, handlers: const {}),
      connectionState: connectionState,
      preferences: preferences,
    );

    await preferences.setInt('fulus_sync_cursor_business-1', 12);

    await resolver.keepLocalVersion('operation-2:conflict');

    final queue = await (db.select(db.syncQueueItems)
          ..where((q) => q.id.equals('operation-2')))
        .getSingle();
    final conflict = await (db.select(db.syncConflictRecords)
          ..where((c) => c.id.equals('operation-2:conflict')))
        .getSingle();

    expect(queue.baseCursor, 12);
    expect(queue.syncAttempts, 0);
    expect(queue.lastError == null, isTrue);
    expect(conflict.resolvedAt == null, isTrue);
  });
}
