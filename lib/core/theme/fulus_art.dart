import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-color Fulus artwork for prominent navigation and action surfaces.
///
/// Keep [FulusIcons] for small utility glyphs such as search, close, check,
/// chevrons, edit and delete. The artwork carries its own colors.
enum FulusArt {
  home('home'),
  sell('sell'),
  stock('stock'),
  money('money'),
  customers('customers'),
  lowStock('low_stock'),
  receipt('receipt'),
  reports('reports'),
  settings('settings'),
  more('more'),
  staff('staff'),
  locations('locations'),
  quickActions('quick_actions'),
  moneyIn('money_in'),
  moneyOut('money_out'),
  creditCard('credit_card');

  const FulusArt(this.file);
  final String file;

  String get asset => 'assets/icons/$file.svg';
}

class FulusArtIcon extends StatelessWidget {
  const FulusArtIcon(
    this.art, {
    super.key,
    this.size = 48,
    this.semanticLabel,
  });

  final FulusArt art;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      art.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
    );
  }
}
