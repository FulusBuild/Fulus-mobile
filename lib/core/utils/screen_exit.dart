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

/// The back-button/gesture counterpart to [ScreenExit.closeScreenOr] —
/// for the exact same raw-`Navigator.push`-vs-go_router mismatch that
/// helper fixes, but for pop attempts [closeScreenOr] never sees
/// because they don't come through an `onPressed` at all:
/// - Android's hardware back button / gesture nav, on a screen this
///   helper wraps.
/// - A pop notification the platform redelivers when a plugin's own
///   external Activity — `file_picker`'s SAF document picker chief
///   among them here — finishes and hands control back to this one.
///   Flutter's `WidgetsBinding.handlePopRoute` fires for this exactly
///   like a real back-press; go_router can't tell the difference.
///
/// Both reach [WidgetsBindingObserver.didPopRoute] and, without this
/// guard, go straight to `GoRouterDelegate.popRoute()` — which throws
/// the same "Null check operator used on a null value" inside
/// `_findCurrentNavigator` that [closeScreenOr]'s own doc comment
/// describes for the button-driven case, except here nothing catches
/// it: the crash happens inside the framework's own route-pop
/// dispatch, not a widget's `onPressed`, so it takes the whole screen
/// down instead of just failing one button tap — this is what turned
/// "choose a backup file" into a black screen requiring a force-close.
///
/// [PopScope] with `canPop: false` intercepts the attempt before
/// go_router's delegate ever sees it, then re-runs it through the
/// identical, already-safe [closeScreenOr] logic — so a hardware back
/// press and the screen's own Cancel/Back button always agree, and
/// neither can reach the crashing code path.
///
/// Same scoping rule as [closeScreenOr] itself: only wrap a screen
/// you've confirmed has no genuine go_router route of its own.
class BackGuard extends StatelessWidget {
  const BackGuard({super.key, required this.fallbackLocation, required this.child});

  /// Passed straight through to [ScreenExit.closeScreenOr] once a pop
  /// is actually handled.
  final String fallbackLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.closeScreenOr(fallbackLocation);
      },
      child: child,
    );
  }
}
