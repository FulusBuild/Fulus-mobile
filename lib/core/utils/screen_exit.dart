import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Closes the current screen correctly regardless of *how it was shown*
/// — a plain `Navigator.push` (as several onboarding screens use, to
/// stay outside go_router's shell branch tree) or a real go_router
/// route, or not "shown" at all in the navigation sense (rendered
/// directly in place by a parent's conditional build, e.g. `_ShellGate`
/// switching between onboarding stages).
///
/// Root cause this fixes: since go_router 3.0, `GoRouter.pop()`
/// (`context.pop()`) and `GoRouter.go()` (`context.go()`) only ever
/// operate on go_router's own declarative page stack — they no longer
/// touch a plain `Navigator` route pushed imperatively on top of it.
/// A screen pushed with `Navigator.push` and closed with `context.pop()`
/// either throws `GoError: There is nothing to pop` (nothing on
/// go_router's stack) or, for `context.go(...)`, silently updates
/// go_router's state while leaving the pushed screen on top — looking
/// like the button did nothing. See docs/dev-history or the onboarding
/// audit (Fulus-onboarding-audit.md) for the concrete bugs this caused:
/// the "Get started" double-tap, the phantom "already set up" dead end,
/// and the false "Couldn't save this product" banner after a
/// successful save.
///
/// Checks, in order:
/// 1. Is there something on go_router's own stack to pop? (True when
///    this screen was reached via `context.push`/`context.pushNamed`.)
///    -> `context.pop()`.
/// 2. Is there something on the plain Navigator to pop? (True when this
///    screen was reached via `Navigator.push`, go_router's own stack
///    untouched.) -> `Navigator.of(context).pop()`.
/// 3. Neither — this screen was rendered directly in place (no push at
///    all), so there's nothing to pop. -> `context.go(fallbackLocation)`
///    to move the app to a new location instead.
extension ScreenExit on BuildContext {
  void closeScreenOr(String fallbackLocation) {
    if (canPop()) {
      pop();
    } else if (Navigator.of(this).canPop()) {
      Navigator.of(this).pop();
    } else {
      go(fallbackLocation);
    }
  }
}
