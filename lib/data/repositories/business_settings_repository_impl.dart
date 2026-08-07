import 'package:drift/drift.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_category.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/business_settings_repository.dart';
import '../local/database/database.dart';
import '../remote/endpoints/business_settings_api.dart';
import 'business_settings_mapper.dart';

class BusinessSettingsRepositoryImpl implements BusinessSettingsRepository {
  BusinessSettingsRepositoryImpl({
    required AppDatabase db,
    required BusinessSettingsApi businessSettingsApi,
    required AuthRepository authRepository,
  })  : _db = db,
        _businessSettingsApi = businessSettingsApi,
        _authRepository = authRepository;

  final AppDatabase _db;
  final BusinessSettingsApi _businessSettingsApi;
  // Depends on AuthRepository directly (unlike AuditRepository, which
  // takes the caller's role as a plain parameter instead) — no cycle
  // risk here, since nothing AuthRepositoryImpl depends on depends back
  // on this class, so there's no reason to push the role-lookup out to
  // every call site the way Audit's genuine circular dependency forced.
  final AuthRepository _authRepository;

  @override
  Stream<BusinessProfile?> watchSettings() {
    final query = _db.select(_db.businessSettings)
      ..where((s) => s.id.equals('singleton'));
    return query.watchSingleOrNull().map((row) => row?.toDomain());
  }

  @override
  Future<bool> hasBeenConfigured() async {
    final existing = await (_db.select(_db.businessSettings)
          ..where((s) => s.id.equals('singleton')))
        .getSingleOrNull();
    return existing != null;
  }

  @override
  Future<void> createBusiness({
    required String businessName,
    required BusinessCategory category,
    required String currencySymbol,
  }) async {
    if (await hasBeenConfigured()) {
      throw const BusinessRuleFailure(
        'This business has already been set up on this device.',
      );
    }

    _validateBusinessName(businessName);
    _validateCurrencySymbol(currencySymbol);

    final defaults = BusinessCategoryDefaults.forCategory(category);

    await _db.into(_db.businessSettings).insert(
          BusinessSettingsCompanion.insert(
            id: 'singleton',
            businessName: businessName,
            currencySymbol: Value(currencySymbol),
            vatEnabled: Value(defaults.vatEnabled),
            vatRate: Value(defaults.vatRate),
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> updateSettings({
    required String businessName,
    String? address,
    String? phone,
    String? email,
    String? tin,
    required bool vatEnabled,
    required double vatRate,
    required String currencySymbol,
    String? receiptFooter,
  }) async {
    // The local check IS the real enforcement now — see
    // AuthFailure.forbidden's doc comment in failure.dart.
    if (_authRepository.currentUser?.role != AuthRole.owner) {
      throw const AuthFailure.forbidden();
    }

    _validateBusinessName(businessName);
    _validateCurrencySymbol(currencySymbol);
    // Mirrors schemas/settings.py's Field(ge=0, le=100) exactly —
    // verified directly.
    if (vatRate < 0 || vatRate > 100) {
      throw const ValidationFailure(
        fieldErrors: {'vatRate': 'VAT rate must be between 0 and 100.'},
      );
    }

    await (_db.update(_db.businessSettings)
          ..where((s) => s.id.equals('singleton')))
        .write(
      BusinessSettingsCompanion(
        businessName: Value(businessName),
        address: Value(address),
        phone: Value(phone),
        email: Value(email),
        tin: Value(tin),
        vatEnabled: Value(vatEnabled),
        vatRate: Value(vatRate),
        currencySymbol: Value(currencySymbol),
        receiptFooter: Value(receiptFooter),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Verified directly: routers/settings.py's PUT endpoint has no
    // audit_service.log() call at all — none of the other 55 real call
    // sites are for settings updates. No audit entry added here either,
    // matching what the real system actually does rather than assuming
    // every mutation should be audited just because Stage 3 exists now.
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
    //
    // Still genuinely useful post-redesign, not vestigial: a Host
    // scenario (Sync layer, deferred) is exactly the case where a
    // second device's locally-created settings should converge with
    // whatever the Host considers authoritative — this just isn't the
    // ONLY way a row gets created anymore, per createBusiness above.
    final response = await _businessSettingsApi.getBusinessProfile();
    await _db.into(_db.businessSettings).insertOnConflictUpdate(response.toDriftCompanion());
  }

  void _validateBusinessName(String businessName) {
    // Mirrors schemas/settings.py's Field(min_length=1, max_length=150)
    // exactly — verified directly.
    if (businessName.isEmpty || businessName.length > 150) {
      throw const ValidationFailure(
        fieldErrors: {
          'businessName': 'Business name must be between 1 and 150 characters.',
        },
      );
    }
  }

  void _validateCurrencySymbol(String currencySymbol) {
    // Mirrors schemas/settings.py's Field(min_length=1, max_length=5)
    // exactly — verified directly.
    if (currencySymbol.isEmpty || currencySymbol.length > 5) {
      throw const ValidationFailure(
        fieldErrors: {
          'currencySymbol': 'Currency symbol must be between 1 and 5 characters.',
        },
      );
    }
  }
}
