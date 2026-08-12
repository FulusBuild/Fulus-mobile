import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/locations_api.dart';
import 'package:fulus_mobile/data/repositories/location_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/sync/handlers/location_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationsApi extends Mock implements LocationsApi {}

void main() {
  late AppDatabase db;
  late MockLocationsApi locationsApi;
  late LocationRepositoryImpl locationRepository;
  late LocationSyncHandler handler;

  setUpAll(() {
    registerFallbackValue(const LocationCreateDto(name: 'fallback'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    locationsApi = MockLocationsApi();
    locationRepository = LocationRepositoryImpl(
      db: db,
      locationsApi: locationsApi,
      syncQueue: SyncQueue(db),
    );
    handler = LocationSyncHandler(
      locationsApi: locationsApi,
      locationRepository: locationRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  SyncQueueItem queueItemFor(Location location, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'location',
      entityLocalId: location.localId,
      operation: operation,
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  test('creates the location on the backend and marks it synced from the response',
      () async {
    final location = await locationRepository.createLocation(
      const LocationDraft(name: 'Downtown'),
    );

    when(() => locationsApi.createLocation(any())).thenAnswer(
      (_) async => Location(
        localId: location.localId,
        serverId: 'server-loc-1',
        name: location.name,
        createdAt: location.createdAt,
        updatedAt: location.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(location));

    final captured = verify(() => locationsApi.createLocation(captureAny())).captured;
    final dto = captured.single as LocationCreateDto;
    expect(dto.name, 'Downtown');

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
    final phantomItem = SyncQueueItem(
      id: 'q1',
      entityType: 'location',
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
