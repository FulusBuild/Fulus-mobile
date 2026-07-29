import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/locations_api.dart';
import 'package:fulus_mobile/data/repositories/location_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationsApi extends Mock implements LocationsApi {}

void main() {
  late AppDatabase db;
  late MockLocationsApi locationsApi;
  late LocationRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    locationsApi = MockLocationsApi();
    repository = LocationRepositoryImpl(db: db, locationsApi: locationsApi);
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
}
