import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/locations_api.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/location_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/sync/handlers/location_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationsApi extends Mock implements LocationsApi {}
class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockLocationsApi locationsApi;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late LocationRepositoryImpl locationRepository;
  late LocationSyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    locationsApi = MockLocationsApi();
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    locationRepository = LocationRepositoryImpl(
      db: db,
      locationsApi: locationsApi,
      syncQueue: SyncQueue(db),
    );
    handler = LocationSyncHandler(
      db: db,
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
      locationRepository: locationRepository,
    );
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));
  });

  tearDown(() => db.close());

  SyncQueueItem queueItemFor(Location location, {String operation = 'create'}) => SyncQueueItem(
    id: 'q1',
    entityType: 'location',
    entityLocalId: location.localId,
    operation: operation,
    priority: 1,
    enqueuedAt: DateTime.now(),
    syncAttempts: 0,
  );

  test('pushes a location through Fulus Cloud and marks it synced', () async {
    final location = await locationRepository.createLocation(
      const LocationDraft(name: 'Downtown'),
    );

    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'),
      operationType: any(named: 'operationType'),
      operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'),
      clientReference: any(named: 'clientReference'),
      payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-loc-1'}});

    await handler.sync(queueItemFor(location));

    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1',
      operationType: 'location.create',
      operationId: 'q1',
      deviceClientId: 'device-client-1',
      clientReference: location.localId,
      payload: any(named: 'payload'),
    )).called(1);

    verifyNever(() => locationsApi.createLocation(any()));

    final updated = await locationRepository.getLocationById(location.localId);
    expect(updated!.serverId, 'server-loc-1');
  });

  test('throws for an operation other than create', () async {
    final location = await locationRepository.createLocation(
      const LocationDraft(name: 'Downtown'),
    );

    await expectLater(
      handler.sync(queueItemFor(location, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    await expectLater(
      handler.sync(SyncQueueItem(
        id: 'q1',
        entityType: 'location',
        entityLocalId: 'never-existed',
        operation: 'create',
        priority: 1,
        enqueuedAt: DateTime.now(),
        syncAttempts: 0,
      )),
      throwsA(isA<StateError>()),
    );
  });
}
