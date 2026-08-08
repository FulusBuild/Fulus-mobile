import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../shared/widgets/widgets.dart';
import 'owner_setup_screen.dart';
import 'sign_in_screen.dart';

/// Decides which first-run experience to show — Volume 3's "Two
/// Journeys" starting point, re-scoped to what's actually buildable
/// right now. [AuthRepository.hasAnyOwnerAccount] answers the same
/// question the backend's old bootstrap-status endpoint used to,
/// purely locally: false means a genuinely fresh install (show
/// [OwnerSetupScreen]), true means a device that's been set up before
/// (show [SignInScreen] — this also covers an employee whose login the
/// owner has already provisioned, since [AuthRepository.login] doesn't
/// distinguish role until after the lookup).
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
/// lands in [OwnerSetupScreen], and every subsequent login — owner or
/// employee — goes through the one real path, [SignInScreen].
///
/// Known open edge case, not solved here: if the app is killed between
/// [OwnerSetupScreen]'s two steps (account created, business not yet),
/// the next launch restores that session (AuthRepositoryImpl persists
/// it the moment the account is created) and lands directly in the app
/// shell with no business configured — this screen is never reached
/// again to finish that second step, since [hasAnyOwnerAccount] is now
/// true. Resuming an interrupted setup is a real gap, but fixing it
/// touches how the shell/Home handles an unconfigured business profile
/// generally, which is Home's own existing concern, not something to
/// patch from this screen. Flagged rather than silently worked around.
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
        return snapshot.data! ? const SignInScreen() : const OwnerSetupScreen();
      },
    );
  }
}
