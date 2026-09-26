import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Canonical Fulus brand mark used in onboarding and account surfaces.
///
/// Workspace headers intentionally use a text-first wordmark, so compact
/// shell sizes collapse to no mark. Larger branding remains available for
/// onboarding and dedicated account surfaces.
class FulusBrandLogo extends StatelessWidget {
  const FulusBrandLogo({
    super.key,
    this.size = 64,
    this.backgroundColor,
    this.padding = 10,
    this.showBackground = true,
  });

  final double size;
  final Color? backgroundColor;
  final double padding;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    if (size <= 48) return const SizedBox.shrink();

    final mark = Image.asset(
      'assets/branding/fulus_mark_transparent.png',
      fit: BoxFit.contain,
      semanticLabel: 'Fulus',
    );

    if (!showBackground) {
      return SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: mark,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: mark,
    );
  }
}
