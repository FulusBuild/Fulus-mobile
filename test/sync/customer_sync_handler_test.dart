import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/customers_api.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/sync/handlers/customer_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCustomersApi extends Mock implements CustomersApi {}

void main() {
  late AppDatabase db;
  late MockCustomersApi customersApi;
  late CustomerRepositoryImpl customerRepository;
  late CustomerSyncHandler handler;

  setUpAll(() {
    registerFallbackValue(const CustomerCreateDto(name: 'fallback'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    customersApi = MockCustomersApi();
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = CustomerSyncHandler(
      customersApi: customersApi,
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

  test(
      'sends the client_reference equal to the local id and marks the '
      'local customer synced from the response', () async {
    final customer = await customerRepository.createCustomer(
      const CustomerDraft(name: 'Chidinma Okafor', phone: '+2348012345678'),
    );

    when(
      () => customersApi.createCustomer(any()),
    ).thenAnswer(
      (_) async => Customer(
        localId: customer.localId,
        serverId: 'server-customer-1',
        name: customer.name,
        phone: customer.phone,
        outstandingBalance: 0,
        purchaseCount: 0,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(customer));

    final captured = verify(() => customersApi.createCustomer(captureAny())).captured;
    final dto = captured.single as CustomerCreateDto;
    expect(dto.clientReference, customer.localId);
    expect(dto.name, 'Chidinma Okafor');

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
