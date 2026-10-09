import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-color Fulus artwork for prominent navigation, action tiles and hubs.
///
/// Keep [FulusIcons] for small utility glyphs such as search, close, check,
/// chevrons, edit and delete. The artwork carries its own colors.
enum FulusArt {
  home('home'),
  sell('sell'),
  stock('stock'),
  money('money'),
  customers('customers'),
  receipt('receipt'),
  reports('reports'),
  staff('staff'),
  locations('locations'),
  notifications('notifications'),
  backup('backup'),
  sync('sync'),
  settings('settings'),
  more('more'),
  stockIn('stock_in'),
  suppliers('suppliers'),
  stockMovement('stock_movement'),
  lowStock('low_stock'),
  category('category'),
  cash('cash'),
  moneyIn('money_in'),
  moneyOut('money_out'),
  scan('scan'),
  quickActions('quick_actions'),
  creditCard('credit_card'),
  payment('payment'),
  bank('bank'),
  splitPayment('split_payment'),
  cloud('cloud'),
  cloudDone('cloud_done'),
  cloudOff('cloud_off'),
  print('print'),
  pdf('pdf'),
  table('table'),
  createBusiness('create_business'),
  signIn('sign_in'),
  joinEmployee('join_employee'),
  offline('offline'),
  printerBluetooth('printer_bluetooth'),
  printerUsb('printer_usb'),
  refund('refund'),
  voidSale('void_sale'),
  restore('restore'),
  calendar('calendar'),
  pin('pin'),
  appLock('app_lock'),
  logout('logout');

  const FulusArt(this.file);
  final String file;
  String get asset => 'assets/icons/$file.svg';
}

class FulusArtIcon extends StatelessWidget {
  const FulusArtIcon(this.art, {super.key, this.size = 48, this.semanticLabel});

  final FulusArt art;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        art.asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticsLabel: semanticLabel,
      );
}
