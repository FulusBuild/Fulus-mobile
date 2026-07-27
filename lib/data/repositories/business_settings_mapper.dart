import 'package:drift/drift.dart';

import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

/// BusinessSettingRow, singular — NOT inferred from Drift's default
/// singularization (BusinessSettings -> BusinessSetting would probably
/// have been right, but "Settings" is enough of an irregular word that
/// leaving it to inference felt like an avoidable risk with no working
/// Dart toolchain in this environment to actually confirm it against).
/// Made explicit instead via @DataClassName('BusinessSettingRow') on the
/// table definition itself (tables.dart) — the same fix Section 6 item 5
/// describes, applied before writing this repository rather than after
/// hitting a collision error, even though this case was never a same-
/// name collision the way Products/Locations were.
extension BusinessSettingRowToDomain on BusinessSettingRow {
  BusinessSettings toDomain() {
    return BusinessSettings(
      businessName: businessName,
      address: address,
      phone: phone,
      email: email,
      tin: tin,
      currencySymbol: currencySymbol,
      vatEnabled: vatEnabled,
      vatRate: vatRate,
      receiptFooter: receiptFooter,
      updatedAt: updatedAt,
    );
  }
}

extension BusinessSettingsResponseDtoToCompanion on BusinessSettingsResponseDto {
  /// Builds the single BusinessSettings row directly from the raw
  /// response — same reasoning as LocationResponseDtoToCompanion: no
  /// Draft/entity round-trip, since this data only ever originates
  /// server-side. id is always the fixed literal 'singleton'
  /// (tables.dart's own comment on that column), never the backend's
  /// real BusinessProfile.id — nothing on the mobile side needs that
  /// server id for anything, since there's no push-sync path back for
  /// this entity to use it on.
  BusinessSettingsCompanion toDriftCompanion() {
    return BusinessSettingsCompanion.insert(
      id: 'singleton',
      businessName: businessName,
      address: Value(address),
      phone: Value(phone),
      email: Value(email),
      tin: Value(tin),
      currencySymbol: Value(currencySymbol),
      vatEnabled: Value(vatEnabled),
      vatRate: Value(vatRate),
      receiptFooter: Value(receiptFooter),
      updatedAt: DateTime.now(),
    );
  }
}
