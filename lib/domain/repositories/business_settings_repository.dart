import '../entities/business_category.dart';
import '../entities/business_settings.dart';

/// Architecture Section 4's repository pattern, applied to the single
/// business-settings row. Was read + pull-sync only, matching the
/// backend's own BusinessProfile having no create/update path for
/// mobile to use — Architecture Redesign changes that: this device's
/// local row is now this device's own source of truth (same reasoning
/// as AuthRepository's Users table), so it needs a genuine local
/// create + update path of its own, not just a mirror of what a server
/// last sent.
///
/// CORRECTED (Architecture Redesign audit pass): the previous
/// read+sync-only shape meant a fresh install couldn't complete "create
/// your business" (Volume 3) — there was no local row at all, and
/// nothing besides syncFromServer() could create one — a direct
/// violation of "must work 100% offline. Everything." createBusiness
/// and updateSettings below close that gap.
abstract class BusinessSettingsRepository {
  /// Reactive by default — the receipt footer, VAT rate, and currency
  /// symbol all feed directly into checkout/receipt rendering (Volume
  /// 4), which must reflect a settings change synced from another
  /// device without a manual refresh.
  Stream<BusinessProfile?> watchSettings();

  /// Whether this device's business has been set up yet at all —
  /// answers the same question hasAnyOwnerAccount() answers for Auth,
  /// for the same reason: a fresh install's onboarding flow needs to
  /// know whether to show "create your business" or skip straight past
  /// it, without a network round-trip to find out.
  Future<bool> hasBeenConfigured();

  /// Creates the local business-settings row — Volume 3's "one flow,
  /// three fields: business name, business type, and currency." Must
  /// only be called when [hasBeenConfigured] is false;
  /// BusinessSettingsRepositoryImpl enforces this itself. [category]
  /// resolves to VAT defaults via BusinessCategoryDefaults — see that
  /// class's own doc comment for why those defaults are currently
  /// uniform across every category rather than genuinely differentiated.
  /// Expected to be called alongside AuthRepository.createFirstOwner as
  /// two steps of the same first-run onboarding flow (separate
  /// repositories, no code-level coupling between them) — whichever
  /// screen ends up driving onboarding is responsible for calling both,
  /// not either repository on its own.
  Future<void> createBusiness({
    required String businessName,
    required BusinessCategory category,
    required String currencySymbol,
  });

  /// Owner-only (mirrors the backend's require_role(UserRole.ADMIN) on
  /// PUT /api/settings/business-profile exactly). Takes the full current
  /// shape rather than the backend's sparse partial-PATCH semantics
  /// (BusinessProfileUpdate's exclude_unset) — a deliberate
  /// simplification: no Settings screen exists yet to know whether a
  /// real sparse-PATCH interaction is actually needed versus a plain
  /// "edit this whole form and save" one, and the latter needs no extra
  /// machinery to express. Revisit if a real screen's UX turns out to
  /// need otherwise. Validated the same way the backend does (verified
  /// directly against schemas/settings.py): businessName 1-150 chars,
  /// vatRate 0-100, currencySymbol 1-5 chars.
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
  });

  Future<void> syncFromServer();

  /// Wipes every locally-owned business record on this device — the
  /// destructive half of the Restore Progress flow's "Start Fresh"
  /// action (`RestoreProgressScreen`), for the one state the rest of
  /// this interface has no other way out of: a `businessSettings`
  /// singleton row survives locally with no matching owner account
  /// (`AuthRepository.hasAnyOwnerAccount()` false), so [createBusiness]
  /// refuses every attempt with "This business has already been set up
  /// on this device" and there is no owner credential left on the
  /// device to sign in and reach [updateSettings] or any other path
  /// that could fix it instead.
  ///
  /// Deletes every row this device holds, not just the businessSettings
  /// singleton — this schema has no per-business id to filter by (one
  /// device, one business, per the singleton pattern), so leaving
  /// Sales/Products/Customers/etc. behind would let old data resurface
  /// the moment a new business is created here. Respects every foreign
  /// key the schema declares (tables.dart) by deleting children before
  /// parents inside one transaction — nothing is left partially
  /// cleared.
  ///
  /// Unconditional once called — no dialog, no "are you sure" here.
  /// Volume 12's "never delete silently" rule is the caller's job
  /// (`RestoreProgressScreen` gates this behind `showFulusConfirmDialog`
  /// per Component Library 5.9), not this method's.
  Future<void> clearLocalBusinessData();
}
