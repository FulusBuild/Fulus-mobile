import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'fulus_button.dart';

/// Nice-to-have gap closure — Volume 3 Decision 8: "Permissions,
/// Requested Contextually... Each system permission dialog is preceded
/// by one plain-language line explaining why, e.g. 'We'll ask to use
/// your camera next — this lets you scan barcodes instead of typing
/// them.'" This is that one line, as its own small dialog rather than a
/// full-screen interstitial — Decision 8 also says permission handling
/// should never feel like a blocker, and a full screen for one sentence
/// would work against that.
///
/// Every call site is expected to have already checked the relevant
/// `DevicePermissions.has*Permission` status first (see that class's own
/// doc comments) and only call this when a real OS dialog is about to
/// follow — this widget has no opinion on that timing itself, it just
/// renders whatever [message] it's given.
///
/// Returns `true` if the owner tapped Continue (proceed to the real OS
/// dialog), `false` for Not now or dismissal — either way, nothing else
/// in the flow is blocked; a `false` here just means the caller skips
/// its own `ensure*` call for this attempt.
Future<bool> showFulusPermissionPrimer(
  BuildContext context, {
  required IconData icon,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(dialogContext),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      // Responsive UI audit — see showFulusConfirmDialog's own note
      // below: caller-supplied [message] plus a small screen or larger
      // system text can otherwise overflow rather than scroll.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryOf(dialogContext), size: AppIconSize.hero),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(dialogContext))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FulusButton(
          label: 'Continue',
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

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
      // Responsive UI audit — off by default on AlertDialog; without
      // it, [title] + [message] together are laid out at their natural
      // height with no permission to give way, so a longer [message]
      // (this is caller-supplied, specific copy per its own doc
      // comment below — not guaranteed short) combined with a small
      // screen or larger system text can overflow the dialog instead of
      // scrolling within it.
      scrollable: true,
      title: Text(title, style: AppTypography.heading.copyWith(fontWeight: FontWeight.w700)),
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
