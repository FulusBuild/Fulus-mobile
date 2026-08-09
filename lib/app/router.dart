import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';
import '../domain/entities/auth_user.dart';
import '../features/auth/presentation/screens/auth_gate_screen.dart';
import '../features/auth/presentation/screens/owner_setup_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/more/employees/presentation/screens/employees_list_screen.dart';
import '../features/more/reports/presentation/screens/reports_screen.dart';
import '../features/more/settings/presentation/screens/backup_screen.dart';
import '../shared/widgets/widgets.dart';
import 'app_shell.dart';
import 'providers.dart';

/// go_router configuration — Architecture Section 1 names this as its
/// own file under app/. Per the brief's rule against building temporary
/// solutions, this is a genuinely real router (real route names, real
/// go_router API), wired to real screens wherever one exists.
///
/// **Foundation phase 2 (App/Home shell + navigation)**: the five
/// top-level destinations (Home, Stock, Sell, Money, More) are now
/// `StatefulShellRoute.indexedStack` branches wrapped in
/// [FulusAppShell]'s persistent bottom nav (Component Library 5.5),
/// each keeping its own independent navigation stack — previously each
/// was a standalone top-level [GoRoute] with no shared chrome and no
/// visible way to move between them at all. Route paths and names are
/// unchanged from before this phase; only how they're grouped changed,
/// so nothing outside this file needed to change.
///
/// **Foundation phase 3 (Owner setup / sign-in)**: the entire shell is
/// gated behind [sessionProvider] rather than reading
/// `ref.watch(authRepositoryProvider).currentUser` directly — that
/// getter isn't reactive (see sessionProvider's own doc comment in
/// providers.dart for why watching it directly silently never rebuilds
/// after a real sign-in). The placeholder previously shown when signed
/// out is now [AuthGateScreen], a real, working owner-setup/sign-in
/// flow.
///
/// **Foundation follow-up (gap closure)**: two things phase 3 originally
/// flagged as open are closed now, both in [_ShellGate] below and this
/// `redirect`:
/// - An owner signed in with no business configured (app killed between
///   [OwnerSetupScreen]'s two steps in an earlier session) used to land
///   straight in the shell with nothing configured. [_ShellGate] now
///   checks [BusinessSettingsRepository.hasBeenConfigured] for a
///   signed-in owner and resumes [OwnerSetupScreen] at its business
///   step instead, before ever building [FulusAppShell].
/// - Employee sessions previously reached `/money` and everything under
///   `/more` exactly like an owner would (Volume 9: "never sees Money,
///   Reports, Employees, or Settings"). [FulusAppShell] hides those nav
///   buttons for an Employee session, but a hidden button alone isn't
///   real enforcement (failure.dart's own `_Forbidden` doc comment makes
///   this same point about permission checks generally) — the
///   `redirect` below is what actually blocks reaching those routes,
///   the same way a direct call bypassing the UI has to be rejected too.
///
/// Named routes (via `name:`) rather than only paths, throughout — so
/// every navigation call site in the app reads as
/// `context.goNamed('home')` rather than a raw path string repeated at
/// every call site, which is exactly the kind of string duplication
/// that drifts silently once a path changes in only one place.
final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final user = ProviderScope.containerOf(context, listen: false).read(sessionProvider);
    if (user == null || user.role == AuthRole.owner) return null;
    // Employee session — Stock stays reachable (see app_shell.dart's
    // own doc comment on why that one is a deliberately conservative
    // reading, not a confirmed spec decision); Money and everything
    // under More do not.
    final blockedForEmployee =
        state.matchedLocation.startsWith('/money') || state.matchedLocation.startsWith('/more');
    return blockedForEmployee ? '/' : null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _ShellGate(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              // HomeScreen takes the signed-in user's id/role as
              // constructor params rather than reading a session
              // provider itself (its own doc comment explains why —
              // testability in isolation) — the shell above already
              // guarantees a signed-in user by the time this builds,
              // but this Consumer stays as the one line that resolves
              // the actual id/role HomeScreen needs, and as a
              // defensive fallback if that guarantee is ever violated.
              builder: (context, state) => Consumer(
                builder: (context, ref, _) {
                  final user = ref.watch(sessionProvider);
                  if (user == null) {
                    return const AuthGateScreen();
                  }
                  return HomeScreen(
                    currentAuthUserId: user.id,
                    isOwner: user.role == AuthRole.owner,
                  );
                },
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock',
              name: 'stock',
              builder: (context, state) => const _PlaceholderScreen(
                title: 'Stock',
                note: 'Volume 6 — inventory. Not yet built.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/sell',
              name: 'sell',
              builder: (context, state) => const _PlaceholderScreen(
                title: 'Sell',
                note: 'Volume 5 — cart, checkout. Not yet built.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/money',
              name: 'money',
              builder: (context, state) => const _PlaceholderScreen(
                title: 'Money',
                note: 'Volumes 7–8 — customers, finance. Not yet built.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              name: 'more',
              builder: (context, state) => const _MoreScreen(),
              routes: [
                GoRoute(
                  path: 'employees',
                  name: 'moreEmployees',
                  builder: (context, state) => const EmployeesListScreen(),
                ),
                GoRoute(
                  path: 'reports',
                  name: 'moreReports',
                  builder: (context, state) => const ReportsScreen(),
                ),
                GoRoute(
                  path: 'settings/backup',
                  name: 'moreSettingsBackup',
                  builder: (context, state) => const BackupScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Resolves to exactly one of three things, in order:
/// [AuthGateScreen] (signed out), [OwnerSetupScreen] resumed at its
/// business step (signed in as an owner with no business configured —
/// the interrupted-setup recovery case), or [FulusAppShell] (the normal
/// case). See the `redirect` above and this router's own header comment
/// for the employee-enforcement half of this same gap-closure pass.
///
/// The business-configured check only runs for an owner session —
/// there's no path to an Employee account existing before a business
/// does (`createEmployeeAccount` is owner-initiated, and an owner
/// wouldn't reach Employees to provision one before their own business
/// setup finished), so checking for Employee sessions would just be an
/// unnecessary database read on every rebuild.
class _ShellGate extends ConsumerStatefulWidget {
  const _ShellGate({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<_ShellGate> createState() => _ShellGateState();
}

class _ShellGateState extends ConsumerState<_ShellGate> {
  // Cached per-user rather than recreated on every rebuild (same reason
  // as AuthGateScreen's own _hasOwnerFuture) — but still recomputed if
  // the signed-in user actually changes, since a fresh sign-in is a
  // genuinely new question, not a stale one.
  AuthUser? _futureBuiltForUser;
  Future<bool>? _businessConfiguredFuture;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) {
      return const AuthGateScreen();
    }
    if (user.role != AuthRole.owner) {
      return FulusAppShell(navigationShell: widget.navigationShell, isOwner: false);
    }

    if (!identical(_futureBuiltForUser, user)) {
      _futureBuiltForUser = user;
      _businessConfiguredFuture = ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
    }

    return FutureBuilder<bool>(
      future: _businessConfiguredFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const FulusScreen(body: FulusLoadingIndicator());
        }
        if (!snapshot.data!) {
          return OwnerSetupScreen(startAtBusinessStep: true, resumingOwner: user);
        }
        return FulusAppShell(navigationShell: widget.navigationShell, isOwner: true);
      },
    );
  }
}

/// **Foundation phase 2**: rebuilt on [FulusScreen]/[FulusListRow] —
/// same three real sub-screens as before, now using the shared
/// components instead of a bare [ListView] of [ListTile]s, as a
/// concrete example of the pattern for whoever builds the rest of
/// Settings. Not the real More/Volume 9-11 landing screen — settings
/// beyond Backup, and a proper Volume 9-11 layout, are still genuinely
/// undone work belonging to whoever picks up Settings.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'More',
      applyPadding: false,
      body: ListView(
        children: [
          FulusListRow(
            title: const Text('Employees'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreEmployees'),
          ),
          const FulusListDivider(indented: false),
          FulusListRow(
            title: const Text('Reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreReports'),
          ),
          const FulusListDivider(indented: false),
          FulusListRow(
            title: const Text('Backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreSettingsBackup'),
          ),
          const FulusListDivider(indented: false),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Volumes 9–11 — the rest of Settings. Not yet built.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A real, minimal screen — not a "TODO screen" with no purpose. Exists
/// specifically so this router is genuinely navigable and verifiable
/// (a widget test can assert each named route renders SOMETHING
/// correctly) while being completely honest on-screen that the real
/// feature isn't built yet, rather than showing a blank screen that
/// could be mistaken for a bug once real navigation exists between
/// tabs. Rebuilt on [FulusScreen] in foundation phase 2 — previously a
/// bare [Scaffold], now the same shared container every real screen
/// should use.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: title,
      body: Center(
        child: Text(
          note,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
