import 'package:flutter/material.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
  });
  final int step;
  final int total;
  final String title;
  @override
  Widget build(BuildContext context) {
    final progress = (step / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FulusBrandLogo(size: 36, backgroundColor: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'BUSINESS SETUP',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondaryOf(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryOf(context).withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$step of $total',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label: '$title, step $step of $total',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.borderOf(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTypography.title.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
