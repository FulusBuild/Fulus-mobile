import '../repositories/auth_repository.dart';
import '../repositories/business_settings_repository.dart';
import '../repositories/location_repository.dart';

/// Closes the "no location-resolution mechanism exists anywhere in the
/// app yet" gap `features/money/domain/money_transaction.dart`'s own
/// doc comment named. Architecture Section 1's "one class per
/// meaningful action" naming example, same shape as
/// `ImportProductsFromCsv`: orchestrates repository *interfaces* (never
/// a concrete Drift type — this file has no data/ or Flutter import
/// anywhere in it, the same Business Engine isolation every other
/// usecase here holds itself to).
///
/// What "resolving the active location" means, in order:
///
/// 1. This device's session already has one recorded
///    ([AuthRepository.getActiveLocationId]) and that location still
///    exists — reuse it as-is, no writes.
/// 2. Otherwise, get-or-create the business's default location
///    ([LocationRepository.getOrCreateDefaultLocation]). This is a
///    cheap, no-op lookup if a location already exists — created by a
///    desktop companion and pulled down via
///    [LocationRepository.syncFromServer], created earlier through the
///    mobile-side location-management screen, or created by a previous
///    call to this same resolver on this or another device sharing the
///    same local backup — and only actually creates a new row on a
///    genuinely fresh, never-yet-resolved install. Named after the
///    business: Volume 3's Business Creation step collects a business
///    name and "nothing else" (its own words) — no location field
///    exists to ask for instead — so the business name is the only
///    user-meaningful label available for a silently-created location,
///    matching Decision 21's "single-location business has exactly one
///    row, created silently at onboarding, no location UI ever
///    surfacing" precedent (tables.dart's own doc comment on the
///    Locations table).
/// 3. Persist whichever location step 1 or 2 landed on as this
///    session's active location
///    ([AuthRepository.setActiveLocationId]), so the next call is a
///    cheap step-1 read instead of repeating this whole resolution.
///
/// Every Sell/Stock/Money call site is expected to go through this one
/// resolver rather than each inventing its own fallback — see
/// `app/providers.dart`'s `activeLocationIdProvider` for the Riverpod-
/// facing wrapper screens actually consume, and
/// `owner_setup_screen.dart`'s `_submitBusiness` for where this first
/// runs, immediately after a fresh business is created.
class ResolveActiveLocation {
  const ResolveActiveLocation({
    required LocationRepository locationRepository,
    required AuthRepository authRepository,
    required BusinessSettingsRepository businessSettingsRepository,
  })  : _locationRepository = locationRepository,
        _authRepository = authRepository,
        _businessSettingsRepository = businessSettingsRepository;

  final LocationRepository _locationRepository;
  final AuthRepository _authRepository;
  final BusinessSettingsRepository _businessSettingsRepository;

  /// Fallback name for the defensive case where step 2 runs before a
  /// business profile exists to name the location after — practically
  /// unreachable in real use, since every real call site sits behind
  /// the app shell, which `_ShellGate` (app/router.dart) only reaches
  /// once `BusinessSettingsRepository.hasBeenConfigured()` is true. Kept
  /// as a defensive default rather than letting that edge case throw,
  /// the same "give a sensible default, don't block the user" spirit
  /// Volume 1's Calmness principle asks for everywhere else.
  static const _fallbackName = 'Main Location';

  Future<String> call() async {
    final storedId = await _authRepository.getActiveLocationId();
    if (storedId != null) {
      final stillExists = await _locationRepository.getLocationById(storedId);
      if (stillExists != null) return storedId;
      // Fall through: the session pointed at a location that's gone
      // (soft-deleted since, or a stale id from restored backup data on
      // a different device's ledger) — re-resolve from scratch below.
    }

    final businessProfile = await _businessSettingsRepository.watchSettings().first;
    final name = businessProfile?.businessName ?? _fallbackName;
    final location = await _locationRepository.getOrCreateDefaultLocation(name: name);

    await _authRepository.setActiveLocationId(location.localId);
    return location.localId;
  }
}
