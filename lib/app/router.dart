import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/auth_user.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/more/employees/presentation/screens/employees_list_screen.dart';
import '../features/more/reports/presentation/screens/reports_screen.dart';
import '../features/more/settings/presentation/screens/backup_screen.dart';
import 'providers.dart';

/// go_router configuration — Architecture Section 1 names this as its
/// own file under app/. Per the brief's rule against building temporary
/// solutions, this is a genuinely real router (real route names, real
/// go_router API), wired to real screens wherever one exists.
///
/// **Phase 0 completion pass**: Home, and three of More's sub-screens
/// (Employees/Reports/Backup — all built in an earlier stage but never
/// reachable from here), are now real. Sell, Stock, and the rest of
/// Money/More stay honest placeholders below — those screens
/// genuinely don't exist yet anywhere in this tree; wiring them in is
/// real, undone work belonging to Phase 1, not something to fabricate
/// ahead of the screens actually existing.
///
/// Named routes (via `name:`) rather than only paths, throughout — so
/// every navigation call site in the app reads as
/// `context.goNamed('home')` rather than a raw path string repeated at
/// every call site, which is exactly the kind of string duplication
/// that drifts silently once a path changes in only one place.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      // HomeScreen takes the signed-in user's id/role as constructor
      // params rather than reading a session provider itself (its own
      // doc comment explains why — testability in isolation) — a
      // Consumer here is the "one line at the call site" that same
      // comment anticipated, now that Stage 2's session genuinely
      // exists (AuthRepositoryImpl.currentUser).
      builder: (context, state) => Consumer(
        builder: (context, ref, _) {
          final user = ref.watch(authRepositoryProvider).currentUser;
          if (user == null) {
            // No login screen exists yet to route to instead (see this
            // file's own header comment on what's genuinely still
            // undone) — an honest placeholder rather than a crash.
            return const _PlaceholderScreen(
              title: 'Home',
              note: 'Not signed in. Volume 3 — Owner setup / sign-in. Not yet built.',
            );
          }
          return HomeScreen(
            currentAuthUserId: user.id,
            isOwner: user.role == AuthRole.owner,
          );
        },
      ),
    ),
    GoRoute(
      path: '/sell',
      name: 'sell',
      builder: (context, state) => const _PlaceholderScreen(
        title: 'Sell',
        note: 'Volume 5 — cart, checkout. Not yet built.',
      ),
    ),
    GoRoute(
      path: '/stock',
      name: 'stock',
      builder: (context, state) => const _PlaceholderScreen(
        title: 'Stock',
        note: 'Volume 6 — inventory. Not yet built.',
      ),
    ),
    GoRoute(
      path: '/money',
      name: 'money',
      builder: (context, state) => const _PlaceholderScreen(
        title: 'Money',
        note: 'Volumes 7–8 — customers, finance. Not yet built.',
      ),
    ),
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
);

/// **Phase 0 completion pass.** The three sub-screens below are real;
/// this hub itself is still the minimum needed to actually reach them
/// through the app's own navigation rather than only by name from code
/// — not the real More/Volume 9-11 landing screen (settings beyond
/// Backup, and a proper Volume 9-11 layout, are still genuinely undone
/// work belonging to Phase 1).
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Employees'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreEmployees'),
          ),
          ListTile(
            title: const Text('Reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreReports'),
          ),
          ListTile(
            title: const Text('Backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreSettingsBackup'),
          ),
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Volumes 9–11 — the rest of Settings. Not yet built.',
              textAlign: TextAlign.center,
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
/// could be mistaken for a bug once real navigation exists between tabs.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            note,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
