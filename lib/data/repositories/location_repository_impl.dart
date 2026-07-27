import 'package:drift/drift.dart';

import '../../domain/entities/location.dart';
import '../../domain/repositories/location_repository.dart';
import '../local/database/database.dart';
import '../remote/endpoints/locations_api.dart';
import 'location_mapper.dart';

class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({
    required AppDatabase db,
    required LocationsApi locationsApi,
  })  : _db = db,
        _locationsApi = locationsApi;

  final AppDatabase _db;
  final LocationsApi _locationsApi;

  @override
  Stream<List<Location>> watchLocations() {
    final query = _db.select(_db.locations)..where((l) => l.deletedAt.isNull());
    return query.watch().map((rows) => rows.map((row) => row.toDomain()).toList());
  }

  @override
  Future<Location?> getLocationById(String localId) async {
    final query = _db.select(_db.locations)..where((l) => l.localId.equals(localId));
    final row = await query.getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> syncFromServer() async {
    // Not paginated (LocationsApi.getLocations's own doc comment) — one
    // call gets everything there is. insertOnConflictUpdate, not
    // InsertMode.insertOrReplace, for the same reason as
    // ProductRepositoryImpl.syncFromServer: Locations has real
    // dependents (Sales/Expenses/IncomeRecords/StockMovements/Shifts
    // all reference Locations.localId), and SQLite's INSERT OR REPLACE
    // deletes-then-reinserts on conflict, which risks disturbing those
    // references during something as routine as a re-sync.
    final response = await _locationsApi.getLocations();
    for (final item in response) {
      await _db.into(_db.locations).insertOnConflictUpdate(item.toDriftCompanion());
    }
  }
}
