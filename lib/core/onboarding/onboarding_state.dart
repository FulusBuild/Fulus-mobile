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

  String _scoped(String base, String? businessId) => businessId == null || businessId.isEmpty ? base : '$base:$businessId';

  static const _firstRunPromptSeenKey = 'fulus_onboarding_first_run_prompt_seen';
  static const _firstSaleCelebratedKey = 'fulus_onboarding_first_sale_celebrated';

  /// Synchronous, like [SyncConfig.isEnabled] — shared_preferences reads
  /// its whole backing store into memory once at `getInstance()`, so
  /// every lookup after that is an in-memory read, not a disk hit. Both
  /// [_ShellGate] (router.dart) and [SaleSuccessScreen] read this
  /// inline, in `build`/`initState`, the same way [_ShellGate] already
  /// reads [SyncConfig]-shaped state elsewhere — no `FutureBuilder`
  /// needed just for this.
  bool hasSeenFirstRunPrompt({String? businessId}) => _preferences.getBool(_scoped(_firstRunPromptSeenKey, businessId)) ?? true;

  bool hasCelebratedFirstSale({String? businessId}) => _preferences.getBool(_scoped(_firstSaleCelebratedKey, businessId)) ?? true;

  /// Called exactly once, by [OwnerSetupScreen._submitBusiness], right
  /// after [BusinessSettingsRepository.createBusiness] succeeds — the
  /// one moment the app can say "this business is new" with certainty.
  /// Flips both flags to `false` together: [FirstRunSetupScreen] and the
  /// first-sale celebration are two beats of the same onboarding story
  /// (Volume 3's "create business → (optional setup) → first sale →
  /// celebration"), so there's no real scenario where one should arm
  /// without the other.
  Future<void> armFirstRun({String? businessId}) async {
    await _preferences.setBool(_scoped(_firstRunPromptSeenKey, businessId), false);
    await _preferences.setBool(_scoped(_firstSaleCelebratedKey, businessId), false);
  }

  /// [FirstRunSetupScreen] calls this the moment the owner acts on ANY
  /// of its options, including "skip" — Volume 3: "Neither screen
  /// blocks progress to First Sale," which this reads as "shown once,
  /// regardless of what's chosen," not "shown until acted on
  /// successfully."
  Future<void> markFirstRunPromptSeen({String? businessId}) => _preferences.setBool(_scoped(_firstRunPromptSeenKey, businessId), true);

  /// [SaleSuccessScreen] calls this once, the moment it decides to
  /// render the celebration variant — not conditioned on the owner
  /// actually tapping anything further, so backing out mid-celebration
  /// still consumes the one-time moment rather than showing it again on
  /// a second sale.
  Future<void> markFirstSaleCelebrated({String? businessId}) => _preferences.setBool(_scoped(_firstSaleCelebratedKey, businessId), true);

  // --- Guided walkthrough ---
  //
  // A separate, more granular tracker from the two flags above, which
  // stay exactly as they are — read by FirstRunSetupScreen and
  // SaleSuccessScreen — until those are folded into the walkthrough in
  // a later milestone. Deliberately just two keys, not a third
  // "isComplete" flag: completion is `walkthroughStep ==
  // OnboardingStep.completion`, not a second fact that could drift out
  // of sync with the first. `null` means the walkthrough hasn't started
  // for this business — armed by whichever screen first detects that no
  // business/user setup exists yet, not by this class itself, the same
  // division of responsibility [armFirstRun] already has with
  // [OwnerSetupScreen].

  static const _walkthroughStepKey = 'fulus_onboarding_walkthrough_step';
  static const _walkthroughSkippedKey = 'fulus_onboarding_walkthrough_skipped_steps';
  static const _walkthroughFirstSaleIdKey = 'fulus_onboarding_walkthrough_first_sale_id';

  OnboardingStep? get walkthroughStep {
    final name = _preferences.getString(_scoped(_walkthroughStepKey, null));
    if (name == null) return null;
    return OnboardingStep.values.asNameMap()[name];
  }

  bool get walkthroughNotStarted => walkthroughStep == null;

  bool get walkthroughCompleted => walkthroughStep == OnboardingStep.completion;

  Set<OnboardingStep> get walkthroughSkippedSteps {
    final names = _preferences.getStringList(_walkthroughSkippedKey) ?? const <String>[];
    final byName = OnboardingStep.values.asNameMap();
    return names.map((name) => byName[name]).whereType<OnboardingStep>().toSet();
  }

  /// Called on entering a step and on finishing the walkthrough alike —
  /// [OnboardingStep.completion] is a real step here, not a separate
  /// method.
  Future<void> advanceWalkthroughTo(OnboardingStep step) =>
      _preferences.setString(_walkthroughStepKey, step.name);

  /// Marks an optional step as explicitly skipped, so resuming the
  /// walkthrough doesn't re-offer it — see [OnboardingStep.isSkippable]
  /// for which steps this applies to.
  Future<void> skipWalkthroughStep(OnboardingStep step) async {
    final updated = walkthroughSkippedSteps..add(step);
    await _preferences.setStringList(
      _walkthroughSkippedKey,
      updated.map((s) => s.name).toList(),
    );
  }

  /// The sale [TransactionVerificationScreen] should look up — recorded
  /// once, at the same moment [advanceWalkthroughTo] moves to
  /// [OnboardingStep.verification], specifically so a second sale made
  /// before the owner ever opens that screen (nothing blocks them from
  /// using the real app in the meantime — see that step's own doc
  /// comment) can't get shown in place of the actual first one.
  String? get walkthroughFirstSaleId => _preferences.getString(_walkthroughFirstSaleIdKey);

  Future<void> recordWalkthroughFirstSale(String saleId) =>
      _preferences.setString(_walkthroughFirstSaleIdKey, saleId);
}

/// The walkthrough's resume points. Coarser than the phases a person
/// actually walks through: [firstSale] covers preparation → cart →
/// payment → success as one resume point, because a mid-sale
/// interruption already has a real source of truth to resume from
/// (DraftCartRepository's own persistence, then this class's own
/// [OnboardingState.hasCelebratedFirstSale] once a sale exists) —
/// tracking a second, finer-grained "which sale sub-step" here would be
/// exactly the duplicate source of truth a walkthrough should avoid.
enum OnboardingStep {
  welcome,
  businessSetup,
  essentialSettings,
  firstProduct,
  navigationIntro,
  firstSale,
  verification,
  completion;

  /// Whether this step can be permanently dismissed without doing it.
  /// businessSetup can't be — the app has nothing to run without it,
  /// already enforced independently of this walkthrough. welcome isn't
  /// something with a separate skip action; proceeding through it IS
  /// the action. firstSale is deferrable (pause, resume later) but not
  /// permanently skippable — reaching a real sale is the walkthrough's
  /// whole point, not something to opt out of once the steps before it
  /// are done. completion is terminal.
  bool get isSkippable => switch (this) {
        welcome || businessSetup || firstSale || completion => false,
        essentialSettings || firstProduct || navigationIntro || verification => true,
      };
}
