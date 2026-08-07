/// The Bible's own fixed five-item list for the "create your business"
/// screen (Volume 3, verified directly, not a guessed set): "a short
/// tappable list — Retail Shop, Restaurant/Food, Pharmacy,
/// Salon/Services, Other — not free text as the primary input."
///
/// Deliberately NOT a column on BusinessProfile/BusinessSettings — the
/// backend model has no such field (verified directly against
/// backend/app/models/settings.py), and Volume 3 itself only describes
/// this as choosing pre-configured defaults at the moment of creation,
/// not something persisted and referenced afterward. Volume 3 also
/// mentions it later seeds Sell's category chips (Volume 13) — that's
/// Inventory's concern (a later stage), not Settings'.
enum BusinessCategory {
  retailShop,
  restaurantOrFood,
  pharmacy,
  salonOrServices,
  other,
}

/// Suggested tax defaults for a chosen [BusinessCategory] — Volume 3:
/// "Business type isn't cosmetic — selecting it pre-configures sensible
/// tax/VAT defaults for that business category," framed as a direct fix
/// for "VAT and tax logic disconnected from the rest of the system"
/// found in the prior backend audit.
///
/// IMPORTANT — honestly incomplete: neither the Bible nor the
/// Architecture doc gives the actual per-category numbers anywhere (both
/// searched directly, not assumed absent) — only the concept and the
/// five category names are specified. Rather than invent plausible-
/// sounding tax rules with no source behind them — a real correctness
/// and compliance risk for whoever's business this is — every category
/// currently resolves to the exact same values the backend's own
/// BusinessProfile columns already default to (verified directly:
/// vat_enabled=False, vat_rate=7.5). This function exists so the
/// mechanism is in place and call sites don't need to change later, but
/// the actual per-category differentiation Volume 3 calls for still
/// needs real product input before this is more than a placeholder that
/// happens to always return the same thing.
class BusinessCategoryDefaults {
  const BusinessCategoryDefaults({
    required this.vatEnabled,
    required this.vatRate,
  });

  final bool vatEnabled;
  final double vatRate;

  static BusinessCategoryDefaults forCategory(BusinessCategory category) {
    // See this class's own doc comment: uniform until real per-category
    // numbers exist to differentiate them.
    return const BusinessCategoryDefaults(vatEnabled: false, vatRate: 7.5);
  }
}
