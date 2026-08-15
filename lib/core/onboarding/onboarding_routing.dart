/// Pure decision logic for where a launch should land, before any UI
/// renders — factored out of [AuthGateScreen] and router.dart's
/// `_ShellGate` so both decisions live in one place, are unit-testable
/// with no widget pump and no real database, and can no longer drift
/// out of sync with each other the way they did before this file
/// existed.
///
/// **Restore Progress bug fix.** Onboarding routing depends on two
/// independent local signals: whether an owner account exists
/// ([AuthRepository.hasAnyOwnerAccount]) and whether a business exists
/// ([BusinessSettingsRepository.hasBeenConfigured]). Before this file
/// existed, [AuthGateScreen] read only the first signal — no owner
/// meant "genuinely fresh install, show GetStartedScreen" — which
/// silently assumed the second signal always agreed. It doesn't
/// always: a `businessSettings` row can survive locally with no
/// matching owner row (an interrupted first run that reached
/// [BusinessSettingsRepository.createBusiness] in an earlier session
/// but never [AuthRepository.createFirstOwner], or a partial local
/// data restore that brought back one table but not the other). That
/// state used to send the owner through a brand-new [OwnerSetupScreen]
/// that succeeds at Step 1 (nothing stops a second owner account being
/// created) and then fails at Step 2 every time, since
/// [BusinessSettingsRepository.createBusiness] rejects a second
/// business unconditionally — a dead end that never resolves on its
/// own. [resolveAuthGateStage] adds the missing third branch so this
/// state routes to `RestoreProgressScreen` instead of a doomed retry
/// loop.
///
/// [resolvePostSignInStage] covers the other half of onboarding
/// routing — the already-signed-in case — router.dart's `_ShellGate`
/// implemented this inline before this file existed (see that class's
/// own doc comment for the interrupted-Step-1-to-Step-2 case it
/// already handled correctly); factored out here for the same
/// testability reason, not because the behavior changed.
library;

/// Where [AuthGateScreen] should route a launch with no active session.
enum AuthGateStage {
  /// No owner account, no business — the ordinary fresh-install case.
  /// Route to GetStartedScreen -> OwnerSetupScreen (both steps, from
  /// scratch).
  needsAccountCreation,

  /// An owner account exists locally — route to SignInScreen. Whether
  /// the business step also still needs finishing is
  /// [resolvePostSignInStage]'s question, not this one; it only
  /// matters once someone is actually signed in.
  needsSignIn,

  /// No owner account, but a business already exists locally — the gap
  /// this file exists to close. Route to `RestoreProgressScreen` so
  /// the owner can choose Continue Setup, Use Existing Business, or
  /// Start Fresh, instead of being funneled into a new-business attempt
  /// that can only ever fail.
  needsRestoreDecision,
}

AuthGateStage resolveAuthGateStage({
  required bool hasOwnerAccount,
  required bool businessConfigured,
}) {
  if (hasOwnerAccount) return AuthGateStage.needsSignIn;
  if (businessConfigured) return AuthGateStage.needsRestoreDecision;
  return AuthGateStage.needsAccountCreation;
}

/// Where `_ShellGate` should route a launch that already has a
/// signed-in owner.
enum PostSignInStage {
  /// Signed in, but no business configured yet — resume
  /// OwnerSetupScreen at its business step rather than restarting
  /// account creation or showing a false duplicate-business warning.
  resumeBusinessSetup,

  /// Business configured, but the one-time first-run nudge hasn't been
  /// shown or dismissed yet — show FirstRunSetupScreen.
  showFirstRunPrompt,

  /// Fully set up — enter the app shell normally.
  enterShell,
}

PostSignInStage resolvePostSignInStage({
  required bool businessConfigured,
  required bool firstRunPromptSeen,
}) {
  if (!businessConfigured) return PostSignInStage.resumeBusinessSetup;
  if (!firstRunPromptSeen) return PostSignInStage.showFirstRunPrompt;
  return PostSignInStage.enterShell;
}
