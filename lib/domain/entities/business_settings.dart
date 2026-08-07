import 'package:json_annotation/json_annotation.dart';

part 'business_settings.g.dart';

/// Mirrors the BusinessSettings table exactly — this device's own
/// source of truth since Stage 4 (Architecture Redesign), not merely a
/// read-only mirror of the backend's singleton BusinessProfile anymore
/// (STALE COMMENT CORRECTED: previously said "read-only from mobile's
/// side, the same desktop-managed reasoning as Location/Product" — true
/// before Stage 4 added createBusiness/updateSettings, not after).
///
/// Named BusinessProfile, not BusinessSettings — CORRECTED: this class
/// was originally named BusinessSettings, identically to the Drift TABLE
/// class in tables.dart (`class BusinessSettings extends Table`, written
/// before this session and left untouched here). @DataClassName only
/// renames the generated ROW class (BusinessSettingRow), not the table
/// class itself — those are two different symbols, and the table class
/// was never the one causing a problem for Locations/Products, since
/// THOSE table classes are plural (Locations, Products) while their
/// domain entities are singular (Location, Product). BusinessSettings
/// never had a clean plural/singular pair the same way — "Settings" is
/// used identically in both forms — so both ended up named identically,
/// which only surfaces as flutter analyze's ambiguous_import the moment
/// one file imports both tables.dart and this file together, exactly
/// what business_settings_mapper.dart does. Renamed the domain side to
/// BusinessProfile instead of the table class, matching the backend's
/// own name for this concept (BusinessProfile/BusinessProfileOut) rather
/// than inventing a third name — and to avoid touching anything in
/// tables.dart that Drift's codegen derives a runtime accessor name from
/// (_db.businessSettings), which isn't verifiable without a working
/// Dart toolchain.
class BusinessProfile {
  const BusinessProfile({
    required this.businessName,
    this.address,
    this.phone,
    this.email,
    this.tin,
    required this.currencySymbol,
    required this.vatEnabled,
    required this.vatRate,
    this.receiptFooter,
    required this.updatedAt,
  });

  final String businessName;
  final String? address;
  final String? phone;
  final String? email;
  final String? tin;
  final String currencySymbol;
  final bool vatEnabled;
  final double vatRate;
  final String? receiptFooter;
  final DateTime updatedAt;
}

/// Mirrors backend/app/schemas/settings.py's BusinessProfileOut exactly,
/// verified directly — the response body for
/// GET /api/settings/business-profile. Still no createToJson (this
/// specific DTO only ever flows server -> mobile, via syncFromServer) —
/// STALE COMMENT CORRECTED: previously justified that by "
/// BusinessSettingsRepository has no create/update method for mobile to
/// push anything back through," which Stage 4 made untrue. The real,
/// still-accurate reason this DTO specifically has no createToJson is
/// narrower: createBusiness/updateSettings write locally only — there's
/// no PUT-equivalent call in BusinessSettingsApi yet for this DTO to
/// serialize a request body for (see that class's own doc comment).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BusinessSettingsResponseDto {
  const BusinessSettingsResponseDto({
    required this.id,
    required this.businessName,
    this.address,
    this.phone,
    this.email,
    this.tin,
    required this.vatEnabled,
    required this.vatRate,
    required this.currencySymbol,
    this.receiptFooter,
  });

  final String id;
  final String businessName;
  final String? address;
  final String? phone;
  final String? email;
  final String? tin;
  final bool vatEnabled;
  final double vatRate;
  final String currencySymbol;
  final String? receiptFooter;

  factory BusinessSettingsResponseDto.fromJson(Map<String, dynamic> json) =>
      _$BusinessSettingsResponseDtoFromJson(json);
}
