import 'package:flutter/widgets.dart';

/// Gap fix: every event in a real diagnostics report came back with
/// `Where: (no screen) -> ...` — `DiagnosticEvent.screen` (see that
/// field's own doc comment) exists specifically to carry "SellScreen"
/// or similar, but nothing anywhere in the app was ever setting it.
/// `installGlobalErrorCapture` (this directory's own
/// global_error_capture.dart) is a top-level function with no
/// BuildContext of its own to read a route name from, so it had
/// nothing to pass — this is the missing piece: a process-wide holder,
/// kept current by [CurrentScreenObserver] below (registered as one of
/// `GoRouter`'s own `observers:` in app/router.dart), that the error
/// hooks can read synchronously at the moment they fire.
///
/// Deliberately not a Riverpod provider or anything else that needs a
/// BuildContext/WidgetRef to read — the whole point is that it has to
/// be readable from code that has neither.
class CurrentScreenTracker {
  CurrentScreenTracker._();

  static String? _current;

  /// The `name:` of the most recently pushed/active GoRoute (e.g.
  /// `'sell'`, `'moneyHistory'`) — the same identifiers already used
  /// throughout the app's own `context.pushNamed(...)` call sites — or
  /// null before the first route has settled (briefly, during the very
  /// first frame) or for a route with no `name:`.
  static String? get current => _current;
}

/// Registered into `GoRouter(observers: [...])` in app/router.dart.
/// Updates [CurrentScreenTracker] on every push/pop/replace — the
/// standard `NavigatorObserver` hooks — reading `route.settings.name`,
/// which GoRouter populates from each `GoRoute`'s own `name:` for
/// named routes (every route in this app's router is named).
class CurrentScreenObserver extends NavigatorObserver {
  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) {
      CurrentScreenTracker._current = name;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _update(newRoute);
}
