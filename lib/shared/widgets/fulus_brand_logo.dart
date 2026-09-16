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
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
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
