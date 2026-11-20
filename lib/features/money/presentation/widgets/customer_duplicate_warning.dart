import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';

/// Advisory returned when a new customer matches an existing phone or email.
class CustomerDuplicateWarning extends StatelessWidget {
  const CustomerDuplicateWarning({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningOf(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.warningOf(context).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.warningOf(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Possible duplicate customer: $message',
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
