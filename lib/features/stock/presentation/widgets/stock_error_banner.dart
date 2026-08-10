import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';

/// A form-level error message — same rationale as the auth feature's
/// own `AuthErrorBanner` (shown above a form when a submission fails
/// for a reason that isn't specific to one field, e.g. a
/// [BusinessRuleFailure] with no field to attach to). Kept as its own
/// small copy here rather than importing across features — feature
/// folders don't reach into each other's `presentation/widgets/`, only
/// into the shared foundation.
class StockErrorBanner extends StatelessWidget {
  const StockErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.errorOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: color, size: AppIconSize.compact),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTypography.body.copyWith(color: color))),
        ],
      ),
    );
  }
}
