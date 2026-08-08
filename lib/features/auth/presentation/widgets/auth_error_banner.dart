import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';

/// A form-level error message — shown above the fields it applies to
/// when a submission fails for a reason that isn't specific to one
/// field (e.g. [AuthFailure.invalidCredentials], which is deliberately
/// generic about whether the username or password was wrong — see
/// failure.dart's own doc comment on why that's intentional, not
/// something a specific field's [FulusTextField.errorText] should
/// pretend to know). Scoped to the auth feature rather than promoted to
/// `shared/widgets/` — no numbered Component Library entry covers a
/// generic banner, so this stays local rather than presented as part of
/// the Bible-sourced foundation.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

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
