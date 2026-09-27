import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Home and stock metric cards share this composition because they have the
/// same hierarchy: icon, label, value, then supporting text.
///
/// The icon is not assigned a visual pixel size. The Expanded/FittedBox pair
/// gives it the remaining space after the card's actual text children and
/// family spacing have been laid out.
class FulusMetricCardColumn extends StatelessWidget {
  const FulusMetricCardColumn({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: Icon(icon, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

/// Customer overview has a deliberately tighter two-line composition than
/// metric cards. Its spacing belongs to this family rather than a global
/// compact-card breakpoint.
class FulusCustomerOverviewColumn extends StatelessWidget {
  const FulusCustomerOverviewColumn({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: Icon(icon, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const SizedBox(height: 2),
        ],
      ],
    );
  }
}

/// Report shortcut cards are intentionally compact: one icon followed by a
/// label. Their composition is independent from metric-card spacing.
class FulusReportCardColumn extends StatelessWidget {
  const FulusReportCardColumn({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: Icon(icon, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}
