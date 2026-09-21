import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/supplier_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/supplier.dart';
import 'package:fulus_mobile/sync/handlers/supplier_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late SupplierRepositoryImpl supplierRepository;
  late SupplierSyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    supplierRepository = SupplierRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
    );
    handler = SupplierSyncHandler(
      supplierRepository: supplierRepository,
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
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
  });

  tearDown(() async => db.close());

  test('supplier edits enqueue an update and sync through the catalog update path',
      () async {
    final created = await supplierRepository.createSupplier(
      const SupplierDraft(
        name: 'Original Supplier',
        phone: '+2348000000000',
      ),
    );
    await supplierRepository.markSynced(
      localId: created.localId,
      serverId: 'server-supplier-1',
    );

    final updated = await supplierRepository.updateSupplier(
      created.localId,
      const SupplierDraft(
        name: 'Updated Supplier',
        phone: '+2348111111111',
        email: 'supplier@example.com',
        address: 'Ibadan',
      ),
    );

    final queued = await (db.select(db.syncQueueItems)
          ..where((q) => q.entityType.equals('supplier'))
          ..where((q) => q.entityLocalId.equals(updated.localId)))
        .getSingle();

    expect(queued.operation, 'update');

    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer(
      (_) async => {
        'data': {'entity_id': 'server-supplier-1'},
      },
    );

    await handler.sync(queued);

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'supplier.update',
          operationId: queued.id,
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);

    final settled = await supplierRepository.getSupplierById(updated.localId);
    expect(settled!.serverId, 'server-supplier-1');
    expect(
      (await db.select(db.syncQueueItems).get()),
      hasLength(1),
      reason: 'SyncEngine owns queue removal; the handler only settles the row.',
    );
  });
}
