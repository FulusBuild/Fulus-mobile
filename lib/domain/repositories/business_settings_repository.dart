import '../entities/business_settings.dart';

/// Architecture Section 4's repository pattern, applied to the single
/// business-settings row. Read + pull-sync only — matches the backend's
/// own BusinessProfile, which has no create/update API of its own
/// either (settings_service.get_profile() always fetches or creates
/// exactly one row; verified directly).
abstract class BusinessSettingsRepository {
  /// Reactive by default — the receipt footer, VAT rate, and currency
  /// symbol all feed directly into checkout/receipt rendering (Volume
  /// 4), which must reflect a settings change synced from another
  /// device without a manual refresh.
  ///
  /// Nullable because there is a real (if brief) window right after a
  /// fresh install, before the first successful syncFromServer() call,
  /// where no local row exists yet at all — unlike the backend's own
  /// get_or_create, which always has something to return.
  Stream<BusinessSettings?> watchSettings();

  Future<void> syncFromServer();
}
