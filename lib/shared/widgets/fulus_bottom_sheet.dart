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
  );
}
