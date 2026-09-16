import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';

/// Shared interaction rules for Phase 7. Keep feedback consistent across
/// high-frequency actions without coupling feature code to platform details.
class FulusHaptics {
  FulusHaptics._();

  static void selection() {
    HapticFeedback.selectionClick();
  }

  static void success() {
    HapticFeedback.mediumImpact();
  }

  static void error() {
    HapticFeedback.heavyImpact();
  }
}

double fulusHorizontalInset(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 360) return AppSpacing.md;
  if (width < 600) return AppSpacing.lg;
  if (width < 900) return AppSpacing.xl;
  return AppSpacing.xxl;
}
