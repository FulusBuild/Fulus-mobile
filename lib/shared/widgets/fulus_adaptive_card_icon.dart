import 'package:flutter/material.dart';

/// Owns the vertical composition of a card family.
///
/// The icon receives the space left after the card's real text children and
/// padding are laid out. Compact cards automatically tighten their gaps rather
/// than applying the same spacing recipe at every size.
class FulusAdaptiveCardColumn extends StatelessWidget {
  const FulusAdaptiveCardColumn({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.compactBreakpoint = 120,
  });

  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final compact = height.isFinite && height < compactBreakpoint;
        final primaryGap = compact ? 4.0 : 8.0;
        final secondaryGap = compact ? 2.0 : 4.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  child: Icon(icon, color: iconColor, size: 100),
                ),
              ),
            ),
            SizedBox(height: primaryGap),
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) SizedBox(height: secondaryGap),
            ],
          ],
        );
      },
    );
  }
}
