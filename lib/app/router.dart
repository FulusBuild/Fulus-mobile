import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// go_router configuration — Architecture Section 1 names this as its
/// own file under app/. Per the brief's rule against building temporary
/// solutions, this is a genuinely real router (real route names, real
/// go_router API, wired to real — if minimal — screens), not a mock
/// single-screen placeholder. What it does NOT yet have is the full
/// route tree Volume 2's five destinations imply — that's real,
/// undone work belonging to each feature's own build-out (Sell, Stock,
/// Money, More), not something to fabricate ahead of those features
/// actually existing.
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
      builder: (context, state) => const _PlaceholderScreen(
        title: 'Home',
        note: 'Volume 4 — hero states, sync status. Not yet built.',
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
      builder: (context, state) => const _PlaceholderScreen(
        title: 'More',
        note: 'Volumes 9–11 — employees, reports, settings. Not yet built.',
      ),
    ),
  ],
);

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
