import 'package:shared_preferences/shared_preferences.dart';

/// Nice-to-have gap closure — Volume 3 (First-Time Experience):
/// "Onboarding polish." Two small, persisted facts this pass needs
/// somewhere durable, and this is that somewhere — same shape as
/// [SyncConfig] (sync/sync_config.dart), right down to why: a plain,
/// non-sensitive on/off value that has no reason to live in the Drift
/// database (no schema migration for a UI-only flag) or Keystore (not
/// remotely sensitive).
///
/// - [hasSeenFirstRunPrompt]: has this owner already been shown (or
///   dismissed) the one-time "add a product / sell now / pair a
///   printer" screen that follows business creation
///   ([FirstRunSetupScreen])?
/// - [hasCelebratedFirstSale]: has this business's actual first sale
///   already gotten its one-time success-celebration treatment on
///   [SaleSuccessScreen]?
///
/// **Both default to `true`** — the inverse of [SyncConfig]'s
/// off-by-default reasoning, and deliberately so. These two keys are
/// only ever written to `false` by [OwnerSetupScreen] at the exact
/// moment a *brand-new* business finishes being created ([armFirstRun]),
/// which is the only point in the app that can honestly claim "nothing
/// has happened in this business yet." Defaulting to `true` means an
/// install that already has these keys unset — every pre-existing
/// business, and any future business created before this file existed
/// — reads as "nothing to show," not as "show the onboarding screen
/// retroactively." An owner who has been running their shop for months
/// should never suddenly see a first-run prompt because of an app
/// update; a `false` default would do exactly that.
class OnboardingState {
  OnboardingState({required SharedPreferences preferences}) : _preferences = preferences;

  /// Async factory rather than a bare constructor — same reason as
  /// [SyncConfig.load]: `SharedPreferences.getInstance()` is itself
  /// async, and bootstrap.dart already awaits a short sequence of these
  /// during startup.
  static Future<OnboardingState> load() async {
    final preferences = await SharedPreferences.getInstance();
    return OnboardingState(preferences: preferences);
  }

  final SharedPreferences _preferences;

  static const _firstRunPromptSeenKey = 'fulus_onboarding_first_run_prompt_seen';
  static const _firstSaleCelebratedKey = 'fulus_onboarding_first_sale_celebrated';

  /// Synchronous, like [SyncConfig.isEnabled] — shared_preferences reads
  /// its whole backing store into memory once at `getInstance()`, so
  /// every lookup after that is an in-memory read, not a disk hit. Both
  /// [_ShellGate] (router.dart) and [SaleSuccessScreen] read this
  /// inline, in `build`/`initState`, the same way [_ShellGate] already
  /// reads [SyncConfig]-shaped state elsewhere — no `FutureBuilder`
  /// needed just for this.
  bool get hasSeenFirstRunPrompt => _preferences.getBool(_firstRunPromptSeenKey) ?? true;

  bool get hasCelebratedFirstSale => _preferences.getBool(_firstSaleCelebratedKey) ?? true;

  /// Called exactly once, by [OwnerSetupScreen._submitBusiness], right
  /// after [BusinessSettingsRepository.createBusiness] succeeds — the
  /// one moment the app can say "this business is new" with certainty.
  /// Flips both flags to `false` together: [FirstRunSetupScreen] and the
  /// first-sale celebration are two beats of the same onboarding story
  /// (Volume 3's "create business → (optional setup) → first sale →
  /// celebration"), so there's no real scenario where one should arm
  /// without the other.
  Future<void> armFirstRun() async {
    await _preferences.setBool(_firstRunPromptSeenKey, false);
    await _preferences.setBool(_firstSaleCelebratedKey, false);
  }

  /// [FirstRunSetupScreen] calls this the moment the owner acts on ANY
  /// of its options, including "skip" — Volume 3: "Neither screen
  /// blocks progress to First Sale," which this reads as "shown once,
  /// regardless of what's chosen," not "shown until acted on
  /// successfully."
  Future<void> markFirstRunPromptSeen() => _preferences.setBool(_firstRunPromptSeenKey, true);

  /// [SaleSuccessScreen] calls this once, the moment it decides to
  /// render the celebration variant — not conditioned on the owner
  /// actually tapping anything further, so backing out mid-celebration
  /// still consumes the one-time moment rather than showing it again on
  /// a second sale.
  Future<void> markFirstSaleCelebrated() => _preferences.setBool(_firstSaleCelebratedKey, true);
}
