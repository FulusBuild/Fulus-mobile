import 'package:flutter/material.dart';

/// The canonical Fulus brand mark used inside the app.
///
/// The source artwork must never be recolored or tinted. Background treatment
/// is controlled independently so the original multi-color Fulus mark remains
/// visually identical wherever it is displayed.
class FulusBrandLogo extends StatelessWidget {
  const FulusBrandLogo({
    super.key,
    this.size = 64,
    this.backgroundColor,
    this.padding = 12,
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
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Image.asset(
        'assets/branding/fulus_logo_master.png',
        fit: BoxFit.contain,
        semanticLabel: 'Fulus',
      ),
    );
  }
}
