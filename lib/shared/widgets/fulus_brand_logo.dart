import 'package:flutter/material.dart';

/// The canonical Fulus brand mark used inside the app.
///
/// The transparent source artwork must never be recolored or tinted. The
/// container supplies the single brand background so the mark does not carry
/// a second nested square behind it.
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
        'assets/branding/fulus_mark_transparent.png',
        fit: BoxFit.contain,
        semanticLabel: 'Fulus',
      ),
    );
  }
}
