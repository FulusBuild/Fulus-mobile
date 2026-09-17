/// Single import point for the shared UI foundation — a Sell/Stock/
/// Money screen should be able to write just:
///
/// ```dart
/// import 'package:fulus_mobile/shared/widgets/widgets.dart';
/// ```
///
/// and get every component below, rather than nine separate imports.
/// Individual files remain independently importable too, for anything
/// that only needs one piece.
library;

export '../../core/theme/fulus_icons.dart';
export '../../core/ux/consumer_polish.dart';
export 'fulus_avatar.dart';
export 'fulus_bottom_sheet.dart';
export 'fulus_brand_logo.dart';
export 'fulus_button.dart';
export 'fulus_card.dart';
export 'fulus_chip.dart';
export 'fulus_dialogs.dart';
export 'fulus_dropdown_field.dart';
export 'fulus_empty_state.dart';
export 'fulus_error_state.dart';
export 'fulus_list_row.dart';
export 'fulus_quick_action.dart';
export 'fulus_screen.dart';
export 'fulus_search_field.dart';
export 'fulus_section_header.dart';
export 'fulus_skeleton.dart';
export 'fulus_snackbar.dart';
export 'fulus_text_field.dart';
export 'pin_keypad.dart';
