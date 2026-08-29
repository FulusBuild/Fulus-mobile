import 'package:flutter/widgets.dart';

/// The single tablet/phone breakpoint this app uses everywhere — 600
/// logical pixels on the shortest side, the standard Material
/// breakpoint. main.dart's own portrait-lock check (run at startup,
/// before any widget tree — and therefore before any [BuildContext] or
/// [MediaQuery] — exists) uses this exact same number via
/// `platformDispatcher.views.first` instead of [isTabletWidth] below,
/// since it has no context to call it with; its own comment names this
/// constant as the reason a future change to where the line sits should
/// move both places together rather than drifting into two
/// differently-tuned thresholds.
const double kTabletBreakpoint = 600;

/// True once the shortest side of the current window is at or past
/// [kTabletBreakpoint] — the reactive, widget-tree counterpart to
/// main.dart's own one-time startup check. Building on that pattern
/// rather than inventing a new one, per Tablet Support's own task
/// requirement: same threshold, same "shortest side" measurement (not
/// width alone, so a tablet held in portrait is still recognized as a
/// tablet), just re-derived per build via [MediaQuery] instead of
/// frozen at whatever main.dart saw at launch — Android's split-screen
/// and freeform window modes can both resize a running app's window
/// without restarting it, and a tablet can simply be rotated, so a
/// value computed once at startup would go stale in either case.
///
/// Used to make an existing screen's layout adapt (a wider max content
/// width, a side-by-side arrangement instead of a stacked one) — never
/// to hide functionality: every feature must stay reachable at every
/// width, per this same requirement's "without disrupting the current
/// Android/phone experience." A phone-width build of this app should
/// never observe a behavior difference from before this constant
/// existed; only genuinely tablet-width windows should see anything
/// change at all.
bool isTabletWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint;
}
