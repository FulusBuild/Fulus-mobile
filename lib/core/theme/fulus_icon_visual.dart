import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'fulus_icons.dart';

/// Fulus object artwork renderer.
///
/// Real-world business objects use the illustrated 2D visual language.
/// Navigation and interaction controls continue to use conventional glyphs.
class FulusIconVisual extends StatelessWidget {
  const FulusIconVisual({
    super.key,
    required this.icon,
    this.size = 24,
    this.color,
  });

  final IconData icon;
  final double size;
  final Color? color;

  String? get _asset {
    if (icon == FulusIcons.home) return 'assets/icons_2d/store.svg';
    if (icon == FulusIcons.sell || icon == FulusIcons.shoppingCart) {
      return 'assets/icons_2d/cart.svg';
    }
    if (icon == FulusIcons.stock ||
        icon == FulusIcons.stockReport ||
        icon == FulusIcons.lowStock) {
      return 'assets/icons_2d/stock.svg';
    }
    if (icon == FulusIcons.money ||
        icon == FulusIcons.navMoney ||
        icon == FulusIcons.cash ||
        icon == FulusIcons.cashBalance ||
        icon == FulusIcons.wallet ||
        icon == FulusIcons.moneyIn ||
        icon == FulusIcons.moneyOut ||
        icon == FulusIcons.payments ||
        icon == FulusIcons.accountBalance) {
      return 'assets/icons_2d/wallet.svg';
    }
    if (icon == FulusIcons.receipt ||
        icon == FulusIcons.expenseReport ||
        icon == FulusIcons.payment ||
        icon == FulusIcons.history) {
      return 'assets/icons_2d/receipt.svg';
    }
    if (icon == FulusIcons.reports ||
        icon == FulusIcons.salesReport ||
        icon == FulusIcons.stockMovement ||
        icon == FulusIcons.tableChart) {
      return 'assets/icons_2d/report.svg';
    }
    if (icon == FulusIcons.customers ||
        icon == FulusIcons.customerReport ||
        icon == FulusIcons.person ||
        icon == FulusIcons.personAdd ||
        icon == FulusIcons.staff) {
      return 'assets/icons_2d/people.svg';
    }
    if (icon == FulusIcons.localShipping || icon == FulusIcons.stockIn) {
      return 'assets/icons_2d/truck.svg';
    }
    if (icon == FulusIcons.print) return 'assets/icons_2d/printer.svg';
    if (icon == FulusIcons.creditCard) return 'assets/icons_2d/card.svg';
    if (icon == FulusIcons.cloud ||
        icon == FulusIcons.cloudOff ||
        icon == FulusIcons.cloudDone ||
        icon == FulusIcons.cloudUpload ||
        icon == FulusIcons.sync ||
        icon == FulusIcons.backup) {
      return 'assets/icons_2d/cloud.svg';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) {
      return Icon(icon, size: size, color: color);
    }

    // Object artwork keeps its own color and shading. Recoloring it with the
    // surrounding text color would flatten the illustration.
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      semanticsLabel: null,
    );
  }
}
