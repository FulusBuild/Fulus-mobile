import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'fulus_button.dart';

/// A blocking destructive-confirmation dialog — Component Library 5.9.
/// "Names the actual consequence and the actual numbers — never a
/// generic 'Are you sure?'" so [message] should be that specific copy,
/// supplied by the caller (this widget only lays the pattern out).
/// Resolves to `true` if the destructive action was confirmed, `false`
/// otherwise (including if dismissed without choosing).
///
/// "Destructive always confirms — a Destructive button never fires its
/// action on first tap alone" (5.1) — a [FulusButton] with
/// [FulusButtonVariant.destructive] should `await` this before its
/// actual destructive logic runs, not the other way around.
Future<bool> showFulusConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: AppTypography.heading),
      content: Text(message, style: AppTypography.body),
      // "Dialog default focus: Cancel/Text button sits visually
      // secondary to the destructive action, but is what a screen
      // reader lands on first" (5.9) — Cancel ordered first below is
      // what gives it that default-focus position in Flutter's own
      // AlertDialog (the first action in the list receives initial
      // focus).
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryOf(dialogContext)),
          child: Text(cancelLabel),
        ),
        FulusButton(
          label: confirmLabel,
          variant: FulusButtonVariant.destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
