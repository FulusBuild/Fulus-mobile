import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Canonical Fulus brand mark used throughout the workspace shell.
///
/// The source artwork is transparent; the container supplies the single
/// Fulus-blue brand background so the mark reads consistently in the drawer,
/// account surfaces, and other shell-level UI.
class FulusBrandLogo extends StatelessWidget {
  const FulusBrandLogo({
    super.key,
    this.size = 64,
    this.backgroundColor,
    this.padding = 10,
  });

  final double size;
  final Color? backgroundColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    // Small shell logos used beside page titles previously had too much
    // internal padding, making the F mark look visibly smaller than the
    // adjacent title even though the blue tile itself was correctly sized.
    // Keep the drawer/account mark unchanged, but let compact 32–40dp marks
    // use the available visual area more effectively.
    final effectivePadding = size <= 40 ? padding.clamp(4.0, 6.0) : padding;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(effectivePadding),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Image.asset(
        'assets/branding/fulus_mark_transparent.png',
        fit: BoxFit.contain,
        semanticLabel: 'Fulus',
      ),
    );
  }
}
