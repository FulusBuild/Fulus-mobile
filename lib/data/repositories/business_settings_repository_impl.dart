import '../../domain/entities/business_settings.dart';
import '../../domain/repositories/business_settings_repository.dart';
import '../local/database/database.dart';
import '../remote/endpoints/business_settings_api.dart';
import 'business_settings_mapper.dart';

class BusinessSettingsRepositoryImpl implements BusinessSettingsRepository {
  BusinessSettingsRepositoryImpl({
    required AppDatabase db,
    required BusinessSettingsApi businessSettingsApi,
  })  : _db = db,
        _businessSettingsApi = businessSettingsApi;

  final AppDatabase _db;
  final BusinessSettingsApi _businessSettingsApi;

  @override
  Stream<BusinessProfile?> watchSettings() {
    final query = _db.select(_db.businessSettings)
      ..where((s) => s.id.equals('singleton'));
    return query.watchSingleOrNull().map((row) => row?.toDomain());
  }

  @override
  Future<void> syncFromServer() async {
    // A single object, not a list — unlike LocationRepositoryImpl's
    // syncFromServer, there's nothing to iterate here.
    // insertOnConflictUpdate for the same reason as Location's own
    // choice over InsertMode.insertOrReplace, even though nothing
    // currently references BusinessSettings.id by foreign key the way
    // Locations.localId is referenced everywhere: consistency with the
    // established convention, not a response to a concrete risk here.
    final response = await _businessSettingsApi.getBusinessProfile();
    await _db.into(_db.businessSettings).insertOnConflictUpdate(response.toDriftCompanion());
  }
}
