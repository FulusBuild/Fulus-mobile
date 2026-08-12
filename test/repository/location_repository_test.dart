import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/locations_api.dart';
import 'package:fulus_mobile/data/repositories/location_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationsApi extends Mock implements LocationsApi {}

void main() {
  late AppDatabase db;
  late MockLocationsApi locationsApi;
  late SyncQueue syncQueue;
  late LocationRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    locationsApi = MockLocationsApi();
    syncQueue = SyncQueue(db);
    repository = LocationRepositoryImpl(db: db, locationsApi: locationsApi, syncQueue: syncQueue);
  });

  tearDown(() async {
    await db.close();
  });

  group('syncFromServer', () {
    test('writes the single default location on first sync', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Main Location')],
      );

      await repository.syncFromServer();

      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
      expect(rows.single.localId, 'loc-1');
      expect(rows.single.serverId, 'loc-1');
      expect(rows.single.name, 'Main Location');
      expect(rows.single.syncStatus, SyncStatus.settled);
    });

    test('writes multiple locations once Phase 2 makes that real', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [
          LocationResponseDto(id: 'loc-1', name: 'Main Location'),
          LocationResponseDto(id: 'loc-2', name: 'Second Shop'),
        ],
      );

      await repository.syncFromServer();

      final rows = await db.select(db.locations).get();
      expect(rows.map((r) => r.localId).toSet(), {'loc-1', 'loc-2'});
    });

    test('re-syncing an existing location updates it rather than duplicating', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Main Location')],
      );
      await repository.syncFromServer();

      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Renamed Location')],
      );
      await repository.syncFromServer();

      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Renamed Location');
    });

    test('an empty response leaves existing locations untouched', () async {
      // Not a real scenario today (there is always at least the one
      // seeded default location — migration 0016_locations on the
      // backend), but insertOnConflictUpdate's whole point is to never
      // delete on a re-sync, unlike InsertMode.insertOrReplace. This
      // guards that choice directly rather than only through the
      // "re-syncing updates rather than duplicating" case above, which
      // wouldn't catch a regression to a delete-then-reinsert strategy
      // if the response also happened to still contain that same row.
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Main Location')],
      );
      await repository.syncFromServer();

      when(() => locationsApi.getLocations()).thenAnswer((_) async => const []);
      await repository.syncFromServer();

      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
    });
  });

  group('watchLocations', () {
    test('emits the synced set reactively', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Main Location')],
      );

      final emissions = <List<Location>>[];
      final sub = repository.watchLocations().listen(emissions.add);

      await repository.syncFromServer();
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, hasLength(1));
      expect(emissions.last.single.name, 'Main Location');

      await sub.cancel();
    });

    test('excludes a soft-deleted location', () async {
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-1',
            name: 'Closed Location',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            deletedAt: Value(DateTime(2026, 6, 1)),
          ));

      final locations = await repository.watchLocations().first;
      expect(locations, isEmpty);
    });
  });

  group('getLocationById', () {
    test('returns the matching location', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Main Location')],
      );
      await repository.syncFromServer();

      final location = await repository.getLocationById('loc-1');
      expect(location, isNotNull);
      expect(location!.name, 'Main Location');
    });

    test('returns null for an id with no local row', () async {
      final location = await repository.getLocationById('does-not-exist');
      expect(location, isNull);
    });
  });

  group('createLocation', () {
    test('writes the location locally as pending', () async {
      final created = await repository.createLocation(const LocationDraft(name: 'Downtown'));

      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
      expect(rows.single.localId, created.localId);
      expect(rows.single.name, 'Downtown');
      expect(rows.single.syncStatus, SyncStatus.pending);
      expect(rows.single.serverId, isNull);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final created = await repository.createLocation(const LocationDraft(name: 'Downtown'));

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'location');
      expect(queued.single.entityLocalId, created.localId);
      expect(queued.single.operation, 'create');
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });
  });

  group('getOrCreateDefaultLocation', () {
    test('creates one when none exist yet', () async {
      final location = await repository.getOrCreateDefaultLocation(name: "Ngozi's Store");

      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
      expect(rows.single.localId, location.localId);
      expect(rows.single.name, "Ngozi's Store");
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('returns the existing location instead of creating a second one', () async {
      when(() => locationsApi.getLocations()).thenAnswer(
        (_) async => const [LocationResponseDto(id: 'loc-1', name: 'Synced From Desktop')],
      );
      await repository.syncFromServer();

      final location = await repository.getOrCreateDefaultLocation(name: 'Should Not Be Used');

      expect(location.localId, 'loc-1');
      expect(location.name, 'Synced From Desktop');
      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
    });

    test('is idempotent across repeated calls', () async {
      final first = await repository.getOrCreateDefaultLocation(name: 'Main Location');
      final second = await repository.getOrCreateDefaultLocation(name: 'Main Location');

      expect(second.localId, first.localId);
      final rows = await db.select(db.locations).get();
      expect(rows, hasLength(1));
    });

    test('picks the earliest-created location when several already exist', () async {
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-older',
            name: 'Older',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: 'loc-newer',
            name: 'Newer',
            createdAt: DateTime(2026, 6, 1),
            updatedAt: DateTime(2026, 6, 1),
            syncStatus: SyncStatus.settled,
          ));

      final location = await repository.getOrCreateDefaultLocation(name: 'Unused');
      expect(location.localId, 'loc-older');
    });
  });

  group('markSynced', () {
    test('sets serverId and settles the row', () async {
      final created = await repository.createLocation(const LocationDraft(name: 'Downtown'));

      await repository.markSynced(localId: created.localId, serverId: 'server-loc-1');

      final row = await (db.select(db.locations)..where((l) => l.localId.equals(created.localId)))
          .getSingle();
      expect(row.serverId, 'server-loc-1');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
}
