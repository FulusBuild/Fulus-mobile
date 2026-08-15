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
/// **Nice-to-have pass (real numbers, replacing the placeholder this
/// class's own comment used to flag)** — sourced directly against
/// Nigeria's VAT rules as they stood in August 2026, not invented:
/// the Nigeria Tax Act 2025 (in force since 1 January 2026, repealing
/// the previous VAT Act) keeps the standard VAT rate at 7.5% (raised
/// from 5% under the 2020 Finance Act, unchanged since), zero-rates
/// "all medical and pharmaceutical products including medicinal herbal
/// products" outright, and raised the small-company VAT-collection
/// exemption threshold from ₦25m to ₦100m annual turnover (with total
/// fixed assets ≤ ₦250m) — verified against multiple independent 2026
/// sources (PwC's tax summary, Baker McKenzie's VAT/GST resource hub,
/// and Nigerian tax-advisory publications from Q1–Q2 2026), not a
/// single unconfirmed one.
///
/// [vatEnabled] here deliberately defaults to `false` for every
/// category, not just "kept uniform because no real numbers exist"
/// (the old placeholder's reasoning) — this app's own README describes
/// its target user as "the kind of business that runs on a single
/// Android phone" (i.e. exactly the small end of the market), and most
/// businesses that size sit under the ₦100m exemption threshold. The
/// app has no turnover figure at onboarding (Volume 3's flow never
/// asks for one) to actually verify that for a given shop, so this
/// defaults to the honest "off, with the real rate pre-filled for the
/// day it's turned on" rather than guessing a shop's registration
/// status it can't know. [vatRate] is real and does differentiate now:
/// 0 for Pharmacy specifically (its core goods are zero-rated
/// regardless of turnover, so the rate that actually applies once VAT
/// is ever switched on for a pharmacy is 0%, not the generic 7.5%),
/// 7.5 for every other category (the standard rate, once a shop grows
/// past the exemption threshold or otherwise chooses to register).
///
/// This is general orientation, not tax advice — thresholds and rates
/// are set by FIRS/the Nigeria Tax Act and can change again; an owner
/// whose turnover is near the threshold should confirm their own
/// registration obligation rather than rely solely on this default.
/// [SettingsMainScreen]'s VAT section surfaces that same caveat next to
/// the toggle for exactly this reason.
class BusinessCategoryDefaults {
  const BusinessCategoryDefaults({
    required this.vatEnabled,
    required this.vatRate,
    required this.guidance,
  });

  final bool vatEnabled;
  final double vatRate;

  /// One line of category-specific "why" — shown as helper text next to
  /// the VAT toggle in Settings/onboarding, so the default doesn't look
  /// like an arbitrary guess. Kept factual and short; not a substitute
  /// for real tax advice, which the class doc comment above says
  /// explicitly.
  final String guidance;

  static BusinessCategoryDefaults forCategory(BusinessCategory category) {
    switch (category) {
      case BusinessCategory.pharmacy:
        return const BusinessCategoryDefaults(
          vatEnabled: false,
          vatRate: 0,
          guidance:
              'Medical and pharmaceutical products are zero-rated under Nigerian VAT law — the rate here is 0% for that reason, not left blank.',
        );
      case BusinessCategory.retailShop:
        return const BusinessCategoryDefaults(
          vatEnabled: false,
          vatRate: 7.5,
          guidance:
              'Off by default — shops under ₦100m annual turnover are exempt from VAT collection. Turn this on once you register, at the standard 7.5% rate.',
        );
      case BusinessCategory.restaurantOrFood:
        return const BusinessCategoryDefaults(
          vatEnabled: false,
          vatRate: 7.5,
          guidance:
              'Off by default under the ₦100m small-business exemption. Note: prepared meals are standard-rated (7.5%), not covered by the zero-rating that applies to raw staple foods.',
        );
      case BusinessCategory.salonOrServices:
        return const BusinessCategoryDefaults(
          vatEnabled: false,
          vatRate: 7.5,
          guidance:
              'Off by default under the ₦100m small-business exemption. Services are standard-rated (7.5%) once you register.',
        );
      case BusinessCategory.other:
        return const BusinessCategoryDefaults(
          vatEnabled: false,
          vatRate: 7.5,
          guidance: 'Off by default under the ₦100m small-business exemption threshold — the standard rate is 7.5% once you register.',
        );
    }
  }
}
