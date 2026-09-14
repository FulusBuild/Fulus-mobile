import 'package:flutter/material.dart';

/// The canonical Fulus brand mark used inside the app.
///
/// Keep the source asset in one place so individual screens cannot drift back
/// to placeholder letters, generic icons, or differently tinted copies of the
/// mark. The transparent mark is the same source used by the native launch
/// artwork and Android launcher foreground.
class FulusBrandLogo extends StatelessWidget {
  const FulusBrandLogo({
    super.key,
    this.size = 64,
    this.backgroundColor,
    this.padding = 12,
    this.tint,
  });

  final double size;
  final Color? backgroundColor;
  final double padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/branding/fulus_mark_transparent.png',
      fit: BoxFit.contain,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.srcIn,
      semanticLabel: 'Fulus',
    );

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: image,
    );
  }
}
