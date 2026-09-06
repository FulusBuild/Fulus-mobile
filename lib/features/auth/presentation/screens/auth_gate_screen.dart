import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_routing.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../shared/widgets/widgets.dart';
import 'backup_restore_decision_screen.dart';
import 'get_started_screen.dart';
import 'identity_picker_screen.dart';
import 'restore_progress_screen.dart';

/// Decides which first-run experience to show — resolved through
/// [resolveAuthGateStage] (core/onboarding/onboarding_routing.dart)
/// rather than the single inline `hasAnyOwnerAccount` check this screen
/// used before that file existed.
///
/// Bug fix, not just a refactor: the old single-signal check silently
/// assumed an owner account and a configured business always agree.
/// They don't always — see [resolveAuthGateStage]'s own doc comment for
/// the exact local state (a `businessSettings` row with no matching
/// owner row) that check missed, and for why it used to send that case
/// into a doomed [OwnerSetupScreen] retry rather than
/// [RestoreProgressScreen]. That screen and [resolveAuthGateStage]
/// itself already existed in this codebase before this fix — this
/// screen was simply never updated to call either, leaving
/// [RestoreProgressScreen] unreachable dead code and this comment
/// describing logic that no longer matched what the rest of onboarding
/// actually did (`_ShellGate` in router.dart already called the
/// [resolveAuthGateStage] counterpart, [resolvePostSignInStage], for
/// its own half of this same routing).
///
/// Volume 3 also describes a second employee-side journey: entering an
/// invite code or scanning a QR to join a business directly, with no
/// sign-in form at all. Deliberately not built here — [AuthRepository]
/// has no method for it (`createEmployeeAccount` is owner-initiated and
/// same-device only), and the Architecture doc explicitly names a
/// cross-device invite/claim flow as "a later-phase capability once
/// Employees has a sync story, not a Phase 0 one." Building UI for a
/// repository method that doesn't exist would be inventing a parallel
/// auth system rather than tracing the real one — so every device
/// without an owner account and no local business data lands in
/// [GetStartedScreen] (or, since Backup & Restore below,
/// [BackupRestoreDecisionScreen] first if a backup is actually
/// detected), and every subsequent same-device switch goes through
/// [IdentityPickerScreen] — see AuthRepository.switchLocalUser's own
/// doc comment for why that replaced a username+password sign-in
/// screen entirely as of the onboarding-simplification pass.
///
/// **Backup & Restore.** [AuthGateStage.needsBackupDecision] is the
/// fresh-reinstall case Backup & Restore's own task requirement names
/// directly: "detect existing backup data automatically on first
/// launch and ask 'Restore or start fresh.'" Detection itself is one
/// extra read alongside the two [resolveAuthGateStage] already took —
/// [BackupRepository.listBackups] against this device's own backups
/// folder (backup_repository_impl.dart's own doc comment covers
/// exactly what that folder does and doesn't survive, and why a picked-
/// from-anywhere file is [BackupRestoreDecisionScreen]'s real fallback
/// for the case this folder-based check alone can't catch).
class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  // All three of resolveAuthGateStage's inputs, combined into one
  // record future rather than three separate FutureBuilders — same
  // reason RestoreProgressScreen's own _detectedFuture combines its
  // two reads. Read once and cached (not built inline in `future:`)
  // for the same reason as every other auth screen's own late-final
  // future: a new Future on every rebuild would re-query the database
  // and flicker back to loading for no reason.
  late final Future<(bool, bool, bool)> _stageInputsFuture = _loadStageInputs();

  Future<(bool, bool, bool)> _loadStageInputs() async {
    final hasOwnerAccount = await ref.read(authRepositoryProvider).hasAnyOwnerAccount();
    final businessConfigured =
        await ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
    // Only worth even asking once the first two signals both say
    // "genuinely nothing local yet" — resolveAuthGateStage's own
    // deliberate check ordering means this answer is thrown away
    // otherwise, so there's no reason to hit the filesystem for it.
    //
    // Gap fix: this used to be listBackups() alone, which only ever
    // finds something on a device that was never actually uninstalled
    // (see that method's own doc comment) — the one case
    // BackupRestoreDecisionScreen's copy already calls "the case
    // AuthGateScreen's automatic check can never catch." A real
    // reinstall used to always fall through to needsAccountCreation
    // regardless of a durable Downloads backup sitting right there,
    // leaving the person to notice and tap "Restore from a backup"
    // themselves — findDurableBackup's own doc comment covers why it,
    // unlike listBackups, actually survives that. Checked second and
    // short-circuited the same way, since it costs a native round-trip
    // this repository provider's own default in bootstrap.dart doesn't
    // need to pay when the app's own folder already answered this.
    final backupRepo = ref.read(backupRepositoryProvider);
    final hasDetectedBackup = !hasOwnerAccount && !businessConfigured
        ? (await backupRepo.listBackups()).isNotEmpty || (await backupRepo.findDurableBackup()) != null
        : false;
    final stage = resolveAuthGateStage(
      hasOwnerAccount: hasOwnerAccount,
      businessConfigured: businessConfigured,
      hasDetectedBackup: hasDetectedBackup,
    );
    // Arms the walkthrough exactly once, at the same moment this
    // screen would show GetStartedScreen for it. Guarded on
    // walkthroughNotStarted so re-entering this future (unlikely in
    // practice — see the class doc comment above on why this is cached
    // — but cheap to guard) never regresses progress made since.
    if (stage == AuthGateStage.needsAccountCreation) {
      final onboardingState = ref.read(onboardingStateProvider);
      if (onboardingState.walkthroughNotStarted) {
        await onboardingState.advanceWalkthroughTo(OnboardingStep.welcome);
        ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.welcome;
      }
    }
    return (hasOwnerAccount, businessConfigured, hasDetectedBackup);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, bool, bool)>(
      future: _stageInputsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Brief and local — genuinely indeterminate (two database
          // reads, not a layout to preview), so a spinner is the right
          // call per 5.18, not a skeleton.
          return const FulusScreen(body: FulusLoadingIndicator());
        }
        final (hasOwnerAccount, businessConfigured, hasDetectedBackup) = snapshot.data!;
        final stage = resolveAuthGateStage(
          hasOwnerAccount: hasOwnerAccount,
          businessConfigured: businessConfigured,
          hasDetectedBackup: hasDetectedBackup,
        );
        switch (stage) {
          case AuthGateStage.needsAccountCreation:
            return const GetStartedScreen();
          case AuthGateStage.needsSignIn:
            return const IdentityPickerScreen();
          case AuthGateStage.needsRestoreDecision:
            return const RestoreProgressScreen();
          case AuthGateStage.needsBackupDecision:
            return const BackupRestoreDecisionScreen();
        }
      },
    );
  }
}
