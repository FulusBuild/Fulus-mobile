import 'package:drift/drift.dart';

import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';

/// BusinessSettingRow, singular — made explicit via
/// @DataClassName('BusinessSettingRow') on the table definition itself
/// (tables.dart), rather than left to Drift's default singularization of
/// the irregular word "Settings" (BusinessSettings -> BusinessSetting
/// would probably have been right, but there was no working Dart
/// toolchain here to actually confirm it against, so this removed the
/// guesswork instead of documenting one). That was never the collision
/// that actually broke flutter analyze, though: the real one was the
/// TABLE class itself (`class BusinessSettings extends Table`, this
/// file's own tables.dart import) sharing an identical name with the
/// domain entity this file also imports — @DataClassName only renames
/// the generated ROW class, not the table class, so it didn't touch
/// that collision at all. Fixed by renaming the domain entity to
/// BusinessProfile instead (business_settings.dart has the full
/// reasoning) — this table class, and its generated
/// BusinessSettingsCompanion/_db.businessSettings accessor below, are
/// untouched.
extension BusinessSettingRowToDomain on BusinessSettingRow {
  BusinessProfile toDomain() {
    return BusinessProfile(
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
