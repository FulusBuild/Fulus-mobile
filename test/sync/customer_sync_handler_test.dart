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

  tearDown(() async {
    await db.close();
  });

  SyncQueueItem queueItemFor(Customer customer, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'customer',
      entityLocalId: customer.localId,
      operation: operation,
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  void stubCloudAuthorization() {
    when(() => fulusConnectionState.selectedBusinessId).thenReturn('business-1');
    when(() => fulusConnectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
  }

  test(
      'sends the client reference and marks the local customer synced from the cloud response',
      () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Chidinma Okafor', phone: '+2348012345678'),
    );
    stubCloudAuthorization();

    when(
      () => fulusSyncApi.submitOperation(
        businessId: any(named: 'businessId'),
        operationType: any(named: 'operationType'),
        operationId: any(named: 'operationId'),
        deviceClientId: any(named: 'deviceClientId'),
        clientReference: any(named: 'clientReference'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer(
      (_) async => {
        'data': {
          'entity_id': 'server-customer-1',
        },
      },
    );

    await handler.sync(queueItemFor(customer));

    final captured = verify(
      () => fulusSyncApi.submitOperation(
        businessId: 'business-1',
        operationType: 'customer.create',
        operationId: 'q1',
        deviceClientId: 'device-client-1',
        clientReference: customer.localId,
        payload: captureAny(named: 'payload'),
      ),
    ).captured;
    final payload = captured.single as Map<String, dynamic>;
    expect(payload['business_id'], 'business-1');
    expect(payload['operation_id'], 'q1');
    expect(payload['client_reference'], customer.localId);
    expect(payload['name'], 'Chidinma Okafor');
    expect(payload['phone'], '+2348012345678');

    final updated = await customerRepository.getCustomerById(customer.localId);
    expect(updated!.serverId, 'server-customer-1');
  });

  test('throws for an operation other than create', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Test Customer'),
    );

    await expectLater(
      handler.sync(queueItemFor(customer, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    final phantomItem = SyncQueueItem(
      id: 'q1',
      entityType: 'customer',
      entityLocalId: 'never-existed',
      operation: 'create',
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );

    await expectLater(
      handler.sync(phantomItem),
      throwsA(isA<StateError>()),
    );
  });
}
