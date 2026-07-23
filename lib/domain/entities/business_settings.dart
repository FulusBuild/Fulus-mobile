/// Mirrors the BusinessSettings table exactly — a local mirror of the
/// backend's singleton BusinessProfile (verified directly against
/// backend/app/models/settings.py), read-only from mobile's side, the
/// same desktop-managed reasoning as Location/Product.
///
/// A real, existing gap worth flagging here rather than silently
/// working around: the mobile BusinessSettings table only has
/// businessName/currencySymbol/vatEnabled/vatRate/receiptFooter —
/// BusinessProfile server-side also has address, phone, email, and tin
/// (Tax Identification Number, used on printed receipts/invoices per
/// that model's own docstring), none of which exist in the mobile
/// schema at all. Whoever builds the concrete sync-down implementation
/// for this repository will need a schema migration adding those four
/// columns first — not something this interface pass should expand the
/// Drift schema to fix on its own.
class BusinessSettings {
  const BusinessSettings({
    required this.businessName,
    required this.currencySymbol,
    required this.vatEnabled,
    required this.vatRate,
    this.receiptFooter,
    required this.updatedAt,
  });

  final String businessName;
  final String currencySymbol;
  final bool vatEnabled;
  final double vatRate;
  final String? receiptFooter;
  final DateTime updatedAt;
}
