import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Fulus icon vocabulary.
///
/// The reference UI uses Google's Material Symbols Outlined family rather
/// than the legacy Material Icons glyphs. Keeping the vocabulary here makes
/// the visual language consistent while screens continue to work with the
/// normal Flutter IconData type.
abstract final class FulusIcons {
  static const home = Symbols.home;
  static const sell = Symbols.point_of_sale;
  static const stock = Symbols.inventory_2;
  static const money = Symbols.payments;
  static const reports = Symbols.bar_chart;
  static const customers = Symbols.groups;
  static const staff = Symbols.badge;
  static const locations = Symbols.location_on;
  static const cloud = Symbols.cloud;
  static const cloudOff = Symbols.cloud_off;
  static const cloudDone = Symbols.cloud_done;
  static const cloudUpload = Symbols.cloud_upload;
  static const warning = Symbols.warning;
  static const settings = Symbols.settings;
  static const menu = Symbols.menu;
  static const search = Symbols.search;
  static const scan = Symbols.qr_code_scanner;
  static const receipt = Symbols.receipt_long;
  static const upload = Symbols.upload_file;
  static const add = Symbols.add;
  static const remove = Symbols.remove;
  static const shoppingCart = Symbols.shopping_cart;
  static const removeShoppingCart = Symbols.remove_shopping_cart;
  static const arrowForward = Symbols.arrow_forward;
  static const arrowBack = Symbols.arrow_back;
  static const arrowUp = Symbols.arrow_upward;
  static const arrowDown = Symbols.arrow_downward;
  static const chevronRight = Symbols.chevron_right;
  static const chevronDown = Symbols.keyboard_arrow_down;
  static const chevronUp = Symbols.keyboard_arrow_up;
  static const error = Symbols.error_outline;
  static const inbox = Symbols.inbox;
  static const image = Symbols.image;
  static const camera = Symbols.camera_alt;
  static const keyboard = Symbols.keyboard;
  static const close = Symbols.close;
  static const more = Symbols.more_vert;
  static const filter = Symbols.filter_list;
  static const filterAlt = Symbols.filter_alt;
  static const sort = Symbols.sort;
  static const category = Symbols.category;
  static const tableChart = Symbols.table_chart;
  static const pictureAsPdf = Symbols.picture_as_pdf;
  static const share = Symbols.share;
  static const searchOff = Symbols.search_off;
  static const calendar = Symbols.calendar_month;
  static const edit = Symbols.edit;
  static const delete = Symbols.delete_outline;
  static const check = Symbols.check;
  static const lock = Symbols.lock_outline;
  static const notifications = Symbols.notifications;
  static const help = Symbols.help_outline;
  static const info = Symbols.info;
  static const backup = Symbols.cloud_upload;
  static const sync = Symbols.sync;
  static const language = Symbols.language;
  static const palette = Symbols.palette;
  static const person = Symbols.person;
  static const logout = Symbols.logout;
  static const backspace = Symbols.backspace;
  static const visibility = Symbols.visibility;
  static const bugReport = Symbols.bug_report;
  static const localShipping = Symbols.local_shipping;
  static const payments = Symbols.payments;
  static const swap = Symbols.swap_vert;
  static const history = Symbols.history;
  static const print = Symbols.print;
}

/// Default visual treatment for Fulus Material Symbols.
const fulusIconTheme = IconThemeData(
  fill: 0,
  weight: 400,
  grade: 0,
  opticalSize: 24,
);
