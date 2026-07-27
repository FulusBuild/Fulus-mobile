import 'package:json_annotation/json_annotation.dart';

part 'business_settings.g.dart';

/// Mirrors the BusinessSettings table exactly — a local mirror of the
/// backend's singleton BusinessProfile (verified directly against
/// backend/app/models/settings.py), read-only from mobile's side, the
/// same desktop-managed reasoning as Location/Product.
///
/// address/phone/email/tin are no longer a gap — CORRECTED: this class
/// (and the Drift table it mirrors) previously only had
/// businessName/currencySymbol/vatEnabled/vatRate/receiptFooter, missing
/// all four of these, which BusinessProfile has always had server-side
/// (address, phone, email, and tin — Tax Identification Number, used on
/// printed receipts/invoices per that model's own docstring). Added here
/// alongside the concrete sync-down implementation this interface was
/// always going to need them for.
class BusinessSettings {
  const BusinessSettings({
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
/// GET /api/settings/business-profile. Deliberately no createToJson,
/// same one-directional reasoning as LocationResponseDto: this only ever
/// flows server -> mobile, since BusinessSettingsRepository has no
/// create/update method for mobile to push anything back through.
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
