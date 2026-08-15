import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../shared/widgets/widgets.dart';
import 'get_started_screen.dart';
import 'owner_setup_screen.dart';
import 'sign_in_screen.dart';

/// Decides which first-run experience to show — Volume 3's "Two
/// Journeys" starting point, re-scoped to what's actually buildable
/// right now. [AuthRepository.hasAnyOwnerAccount] answers the same
/// question the backend's old bootstrap-status endpoint used to,
/// purely locally: false means a genuinely fresh install (show
/// [GetStartedScreen], which is itself just a single tap away from
/// [OwnerSetupScreen] — see that screen's own doc comment for why it
/// sits in front of the form rather than replacing it), true means a
/// device that's been set up before (show [SignInScreen] — this also
/// covers an employee whose login the owner has already provisioned,
/// since [AuthRepository.login] doesn't distinguish role until after
/// the lookup).
///
/// Volume 3 also describes a second employee-side journey: entering an
/// invite code or scanning a QR to join a business directly, with no
/// sign-in form at all. Deliberately not built here —
/// [AuthRepository] has no method for it
/// (`createEmployeeAccount` is owner-initiated and same-device only),
/// and the Architecture doc explicitly names a cross-device invite/
/// claim flow as "a later-phase capability once Employees has a sync
/// story, not a Phase 0 one." Building UI for a repository method that
/// doesn't exist would be inventing a parallel auth system rather than
/// tracing the real one (the one rule this whole phase was told not to
/// break) — so for now, every device without an owner account yet
/// lands in [GetStartedScreen] → [OwnerSetupScreen], and every
/// subsequent login — owner or employee — goes through the one real
/// path, [SignInScreen].
///
/// Doc correction, not a behavior change: this comment previously
/// flagged an "open edge case" here — the app killed mid-[
/// OwnerSetupScreen] (account created, business not yet) landing in a
/// dead end on relaunch. That's not actually true of the app as it
/// stands: `_ShellGate` (router.dart) already checks
/// `BusinessSettingsRepository.hasBeenConfigured()` for exactly this
/// case and resumes at `OwnerSetupScreen(startAtBusinessStep: true,
/// resumingOwner: user)` — see that class's own doc comment. This
/// screen was simply never the right place that resume logic could
/// live (by the time [hasAnyOwnerAccount] is true, this screen isn't
/// reached again, same reasoning the old comment already had right),
/// so nothing here changed; the comment describing it as unsolved was
/// just stale.
class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  // Read once and cached, rather than as the `future:` argument directly
  // in build() — a new Future built on every rebuild would re-query the
  // database and can flicker FutureBuilder back to its loading state
  // for no reason.
  late final Future<bool> _hasOwnerFuture = ref.read(authRepositoryProvider).hasAnyOwnerAccount();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasOwnerFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Brief and local — genuinely indeterminate (a database read,
          // not a layout to preview), so a spinner is the right call
          // per 5.18, not a skeleton.
          return const FulusScreen(body: FulusLoadingIndicator());
        }
        return snapshot.data! ? const SignInScreen() : const GetStartedScreen();
      },
    );
  }
}
