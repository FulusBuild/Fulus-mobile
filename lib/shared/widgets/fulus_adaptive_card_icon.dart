import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/fulus_icons.dart';

/// A card icon whose visual size emerges from the card's actual constraints.
///
/// The card owns padding, typography and gaps. This widget only consumes the
/// space left for the icon and fits the glyph into that space. Compact cards
/// therefore become tighter as a composition rather than being assigned a
/// smaller global icon token.
class FulusAdaptiveCardIcon extends StatelessWidget {
  const FulusAdaptiveCardIcon({
    super.key,
    required this.icon,
    required this.color,
    this.compactBreakpoint = 120,
  });

  final IconData icon;
  final Color color;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight.isFinite &&
            constraints.maxHeight < compactBreakpoint;
        final gap = compact ? 4.0 : 8.0;
        final microGap = compact ? 2.0 : 4.0;
        return _AdaptiveIconColumn(
          icon: icon,
          color: color,
          gap: gap,
          microGap: microGap,
        );
      },
    );
  }
}

class _AdaptiveIconColumn extends StatelessWidget {
  const _AdaptiveIconColumn({
    required this.icon,
    required this.color,
    required this.gap,
    required this.microGap,
  });

  final IconData icon;
  final Color color;
  final double gap;
  final double microGap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Icon(icon, color: color, size: 100),
      ),
    );
  }
}

/// Shared spacing policy for vertical card compositions.
///
/// Small cards use tighter inter-element gaps; larger cards get more breathing
/// room. The values are intentionally owned by the card family rather than by
/// the global icon-size token layer.
class FulusCardGap {
  FulusCardGap._();

  static double primary(double height) => height < 120 ? 4 : 8;
  static double secondary(double height) => height < 120 ? 2 : 4;
}
