import 'package:flutter/widgets.dart';

/// Window-width breakpoint used for adaptive UI. Layout decisions are based
/// on the space the app actually has, not a physical device type.
const double kTabletBreakpoint = 600;

/// True when the current app window is wide enough for tablet-style layouts.
/// This intentionally uses window width so split-screen, freeform windows and
/// rotation adapt immediately instead of relying on a device classification.
bool isTabletWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= kTabletBreakpoint;
}
