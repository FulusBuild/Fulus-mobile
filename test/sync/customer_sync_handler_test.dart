import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';
import 'package:fulus_mobile/sync/handlers/customer_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockLocationRepository extends Mock implements LocationRepository {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState fulusConnectionState;
  late CustomerRepositoryImpl customerRepository;
  late MockLocationRepository locationRepository;
  late CustomerSyncHandler handler;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fulusSyncApi = MockFulusSyncApi();
    fulusConnectionState = MockFulusConnectionState();
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    locationRepository = MockLocationRepository();
    when(() => locationRepository.getLocationById('loc-1')).thenAnswer((_) async => Location(
      localId: 'loc-1', serverId: 'server-location-1', name: 'Main Store',
      createdAt: DateTime.utc(2026, 1, 1), updatedAt: DateTime.utc(2026, 1, 1),
    ));
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'loc-1', serverId: const Value('server-location-1'), name: 'Main Store',
      createdAt: DateTime.utc(2026, 1, 1), updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));
    await db.into(db.users).insert(UsersCompanion.insert(
      localId: 'owner-user',
      fullName: 'Owner',
      role: AuthRole.owner,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));
    await db.into(db.sessions).insert(SessionsCompanion.insert(
      id: 'current',
      userId: 'owner-user',
      activeLocationId: const Value('loc-1'),
    ));
    handler = CustomerSyncHandler(
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: fulusConnectionState,
      customerRepository: customerRepository,
      locationRepository: locationRepository,
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
      CustomerDraft(name: 'Chidinma Okafor', locationId: 'loc-1', phone: '+2348012345678', creditLimit: moneyFromMajor(300)),
    );
    stubCloudAuthorization();
    final submittedPayloads = <String, Map<String, dynamic>>{};
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'), operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'), deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      final operationType = invocation.namedArguments[#operationType] as String;
      submittedPayloads[operationType] = Map<String, dynamic>.from(
        invocation.namedArguments[#payload] as Map,
      );
      return {'data': {'entity_id': 'server-customer-1'}};
    });

    await handler.sync(queueItemFor(customer));

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1', operationType: 'customer.create', operationId: 'q1',
          deviceClientId: 'device-client-1', clientReference: customer.localId,
          payload: any(named: 'payload'),
        )).called(1);
    expect((await customerRepository.getCustomerById(customer.localId))!.serverId, 'server-customer-1');
    expect(submittedPayloads['customer.create']?['credit_limit'], '300.00');
  });

  test('serializes a null credit limit as a decimal money string', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'No Credit Limit', locationId: 'loc-1', phone: '+2348000000000'),
    );
    stubCloudAuthorization();
    Map<String, dynamic>? submittedPayload;
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      submittedPayload = Map<String, dynamic>.from(
        invocation.namedArguments[#payload] as Map,
      );
      return {'data': {'entity_id': 'server-customer-null-limit'}};
    });

    await handler.sync(queueItemFor(customer));

    expect(submittedPayload?['credit_limit'], '0.00');
  });

  test('archives an offline-created customer after cloud create', () async {
    final customer = await customerRepository.createCustomer(
      CustomerDraft(name: 'Offline Archived', locationId: 'loc-1', phone: '+2348000000000', creditLimit: moneyFromMajor(300)),
    );
    await customerRepository.archiveCustomer(customer.localId);

    stubCloudAuthorization();
    final submittedPayloads = <String, Map<String, dynamic>>{};
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      final operationType = invocation.namedArguments[#operationType] as String;
      submittedPayloads[operationType] = Map<String, dynamic>.from(invocation.namedArguments[#payload] as Map);
      return {
        'data': {
          'entity_id': 'server-customer-1',
          'status': operationType == 'customer.create' ? 'applied' : 'updated',
        },
      };
    });

    await handler.sync(queueItemFor(customer));

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'customer.create',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: customer.localId,
          payload: any(named: 'payload'),
        )).called(1);
    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'customer.update',
          operationId: 'q1:archive',
          deviceClientId: 'device-client-1',
          clientReference: customer.localId,
          payload: any(named: 'payload'),
        )).called(1);
    expect((await customerRepository.getCustomerById(customer.localId))!.serverId, 'server-customer-1');
    expect(submittedPayloads['customer.create']?['credit_limit'], '300.00');
    expect(submittedPayloads['customer.update']?['credit_limit'], '300.00');
  });

  test('pushes a customer update through Fulus Cloud', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Test Customer', locationId: 'loc-1', phone: '+2348000000000'),
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
