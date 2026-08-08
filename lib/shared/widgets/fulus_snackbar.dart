import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A non-blocking confirmation that something already happened —
/// Component Library 5.10. Bottom-anchored, auto-dismisses after ~4
/// seconds, one optional action ("Undo" being 5.10's own named case:
/// "Delete fires immediately with an Undo window, rather than a Dialog
/// asking permission first"). "Never stacks more than one at a time —
/// a second replaces the first," achieved here by clearing any
/// snackbar already showing before presenting the new one.
void showFulusSnackbar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: AppTypography.body.copyWith(color: AppColors.neutral0)),
      backgroundColor: AppColors.neutral900,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}, textColor: AppColors.primary300),
    ),
  );
}
