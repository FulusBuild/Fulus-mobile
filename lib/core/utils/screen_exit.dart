import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Closes the current screen correctly whether it was shown with a
/// plain `Navigator.push` (several onboarding screens use this, to
/// stay outside go_router's shell branch tree) or rendered directly in
/// place by a parent's conditional build (e.g. `_ShellGate` switching
/// between onboarding stages, with nothing pushed at all).
///
/// Root cause this fixes: several onboarding screens originally closed
/// with `context.pop()`/`context.go()`. Since go_router 3.0, those only
/// operate on go_router's own declarative page stack, not a plain
/// `Navigator` route pushed on top of it — so on a screen that was
/// merely `Navigator.push`-ed, `context.go(...)` silently updated
/// go_router's state while leaving the screen on top (looking like the
/// button did nothing — the "Get started" double-tap, the phantom
/// "already set up" dead end), and `context.pop()` was worse: it threw
/// `GoError: There is nothing to pop`.
///
/// go_router's own `canPop()` is NOT a safe way to tell these cases
/// apart in an app built on `StatefulShellRoute` (as this one is):
/// `canPop()` reflects the *overall* match-list depth of the whole
/// router (shell + active branch), which is already >1 almost all the
/// time regardless of whether the *current* screen is one of
/// go_router's own tracked pages. Trusting it here caused `pop()` to
/// run against a context go_router never actually registered, which
/// crashed inside `GoRouterDelegate._findCurrentNavigator` with "Null
/// check operator used on a null value" — worse than the bug it
/// replaced, since that one broke a screen and this one crashed the
/// app. So this helper only ever asks the plain `Navigator` — a local,
/// framework-level check that isn't affected by go_router's shell
/// structure — never go_router's own `canPop()`/`pop()`.
///
/// Only use this on a screen you've confirmed is *never* reached via a
/// real go_router route (`context.push`/`pushNamed`/a `GoRoute`
/// builder) — if it has a genuine go_router entry point too (like
/// `AddEditProductScreen`, reached both by onboarding's raw push and
/// the Stock tab's real `stockAddProduct` route), guessing at runtime
/// isn't safe; branch on an explicit constructor flag set by each
/// caller instead, and use `context.pop()` for the go_router-pushed
/// path directly.
extension ScreenExit on BuildContext {
  void closeScreenOr(String fallbackLocation) {
    final navigator = Navigator.of(this);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      go(fallbackLocation);
    }
  }
}
