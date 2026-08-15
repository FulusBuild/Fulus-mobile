import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_routing.dart';
import '../../../../shared/widgets/widgets.dart';
import 'get_started_screen.dart';
import 'restore_progress_screen.dart';
import 'sign_in_screen.dart';

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
/// [GetStartedScreen], and every subsequent login goes through
/// [SignInScreen].
class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  // Both of resolveAuthGateStage's inputs, combined into one record
  // future rather than two separate FutureBuilders — same reason
  // RestoreProgressScreen's own _detectedFuture combines its two reads.
  // Read once and cached (not built inline in `future:`) for the same
  // reason as every other auth screen's own late-final future: a new
  // Future on every rebuild would re-query the database and flicker
  // back to loading for no reason.
  late final Future<(bool, bool)> _stageInputsFuture = _loadStageInputs();

  Future<(bool, bool)> _loadStageInputs() async {
    final hasOwnerAccount = await ref.read(authRepositoryProvider).hasAnyOwnerAccount();
    final businessConfigured =
        await ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
    return (hasOwnerAccount, businessConfigured);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, bool)>(
      future: _stageInputsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Brief and local — genuinely indeterminate (two database
          // reads, not a layout to preview), so a spinner is the right
          // call per 5.18, not a skeleton.
          return const FulusScreen(body: FulusLoadingIndicator());
        }
        final (hasOwnerAccount, businessConfigured) = snapshot.data!;
        final stage = resolveAuthGateStage(
          hasOwnerAccount: hasOwnerAccount,
          businessConfigured: businessConfigured,
        );
        switch (stage) {
          case AuthGateStage.needsAccountCreation:
            return const GetStartedScreen();
          case AuthGateStage.needsSignIn:
            return const SignInScreen();
          case AuthGateStage.needsRestoreDecision:
            return const RestoreProgressScreen();
        }
      },
    );
  }
}
