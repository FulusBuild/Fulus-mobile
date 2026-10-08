import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'fulus_icons.dart';

/// Renders Fulus semantic objects using the flat, dimensional 2D artwork
/// used by the current visual direction.
///
/// Important rule: objects may be illustrated; controls remain conventional
/// glyphs. This prevents the interface from becoming noisy or toy-like.
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
        icon == FulusIcons.payment) {
      return 'assets/icons_2d/receipt.svg';
    }
    if (icon == FulusIcons.reports ||
        icon == FulusIcons.salesReport ||
        icon == FulusIcons.stockMovement ||
        icon == FulusIcons.tableChart) {
      return 'assets/icons_2d/chart.svg';
    }
    if (icon == FulusIcons.customers ||
        icon == FulusIcons.customerReport ||
        icon == FulusIcons.person ||
        icon == FulusIcons.personAdd) {
      return 'assets/icons_2d/people.svg';
    }
    if (icon == FulusIcons.staff) return 'assets/icons_2d/staff.svg';
    if (icon == FulusIcons.localShipping || icon == FulusIcons.stockIn) {
      return 'assets/icons_2d/truck.svg';
    }
    if (icon == FulusIcons.print) return 'assets/icons_2d/printer.svg';
    if (icon == FulusIcons.scan) return 'assets/icons_2d/scanner.svg';
    if (icon == FulusIcons.cloud ||
        icon == FulusIcons.cloudOff ||
        icon == FulusIcons.cloudDone ||
        icon == FulusIcons.cloudUpload ||
        icon == FulusIcons.sync) {
      return 'assets/icons_2d/cloud.svg';
    }
    if (icon == FulusIcons.backup) return 'assets/icons_2d/backup.svg';
    if (icon == FulusIcons.lock) return 'assets/icons_2d/lock.svg';
    if (icon == FulusIcons.creditCard) return 'assets/icons_2d/card.svg';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) {
      return Icon(icon, size: size, color: color);
    }

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: null,
    );
  }
}
