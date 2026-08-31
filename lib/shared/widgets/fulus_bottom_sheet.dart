import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Wraps [showModalBottomSheet] with the Bible's own sheet chrome —
/// 20dp top corners only (`AppRadius.lg`, per 5.9: "softer and larger
/// than a card's, since a sheet is momentarily the entire foreground"),
/// an optional [title], and keyboard-aware bottom padding
/// (`isScrollControlled: true`).
///
/// Dismissal — tapping the dimmed area or swiping down — is
/// [showModalBottomSheet]'s own default behavior, matching 5.9's rule
/// that both must always work, "never a single hidden gesture as the
/// only way out."
///
/// Responsive UI audit — [builder]'s content now sits inside a
/// [SingleChildScrollView] instead of a bare [Column]. The modal route
/// itself (via `isScrollControlled: true`) already bounds how tall this
/// sheet can get to the available window height; what was missing was
/// anything that let content *taller than that bound* degrade
/// gracefully. A plain Column can't shrink, so a sheet whose content —
/// plus an open keyboard, plus a small screen — added up to more than
/// the available height had nowhere to go but a bottom overflow, the
/// same "content taller than the box guessed for it" failure as the
/// stat cards, just triggered by the keyboard instead of a font size.
/// Every current call site's content is short enough that this is
/// invisible today; it's here so a future sheet with more fields, or
/// the same sheet on a genuinely small phone with the keyboard up,
/// scrolls instead of throwing a render error.
Future<T?> showFulusBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
}) {
  final backgroundColor = AppColors.surfaceOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: backgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title, style: AppTypography.heading),
                const SizedBox(height: AppSpacing.lg),
              ],
              builder(sheetContext),
            ],
          ),
        ),
      ),
    ),
  );
}
