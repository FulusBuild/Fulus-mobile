import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/sync/handlers/customer_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState fulusConnectionState;
  late CustomerRepositoryImpl customerRepository;
  late CustomerSyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fulusSyncApi = MockFulusSyncApi();
    fulusConnectionState = MockFulusConnectionState();
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = CustomerSyncHandler(
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: fulusConnectionState,
      customerRepository: customerRepository,
    );
  });

  tearDown(() async => db.close());

  SyncQueueItem queueItemFor(Customer customer, {String operation = 'create'}) => SyncQueueItem(
        id: 'q1', entityType: 'customer', entityLocalId: customer.localId,
        operation: operation, priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
      );

  void stubCloudAuthorization() {
    when(() => fulusConnectionState.selectedBusinessId).thenReturn('business-1');
    when(() => fulusConnectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1', businessId: 'business-1', deviceClientId: 'device-client-1', status: 'active',
      ),
    );
  }

  test('pushes customer through Fulus Cloud and reconciles the server id', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Chidinma Okafor', phone: '+2348012345678'),
    );
    stubCloudAuthorization();
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'), operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'), deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
        )).thenAnswer((_) async => {'data': {'entity_id': 'server-customer-1'}});

    await handler.sync(queueItemFor(customer));

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1', operationType: 'customer.create', operationId: 'q1',
          deviceClientId: 'device-client-1', clientReference: customer.localId,
          payload: any(named: 'payload'),
        )).called(1);
    expect((await customerRepository.getCustomerById(customer.localId))!.serverId, 'server-customer-1');
  });

  test('creates an offline-archived customer as inactive in one cloud operation', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Offline Archived', phone: '+2348000000000'),
    );
    await customerRepository.archiveCustomer(customer.localId);

    stubCloudAuthorization();
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
          'data': {
            'entity_id': 'server-customer-1',
            'status': 'applied',
          },
        });

    await handler.sync(queueItemFor(customer));

    final captured = verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'customer.create',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: customer.localId,
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    expect(captured['is_active'], isFalse);
    expect(captured['server_id'], isNull);
    expect((await customerRepository.getCustomerById(customer.localId))!.serverId, 'server-customer-1');
  });

  test('pushes a customer update through Fulus Cloud', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Test Customer', phone: '+2348000000000'),
    );
    await customerRepository.markSynced(
      localId: customer.localId,
      serverId: 'server-customer-1',
    );
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.entityLocalId.equals(customer.localId)))
        .go();
    final updated = await customerRepository.updateCustomer(
      customer.localId,
      const CustomerDraft(name: 'Updated Customer', phone: '+2348111111111'),
    );

    stubCloudAuthorization();
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {'data': {'entity_id': 'server-customer-1'}});

    await handler.sync(queueItemFor(updated, operation: 'update'));

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'customer.update',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: updated.localId,
          payload: any(named: 'payload'),
        )).called(1);
  });

  test('throws when the queue item has outlived its local row', () async {
    await expectLater(handler.sync(SyncQueueItem(
      id: 'q1', entityType: 'customer', entityLocalId: 'never-existed', operation: 'create',
      priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
    )), throwsA(isA<StateError>()));
  });
}
