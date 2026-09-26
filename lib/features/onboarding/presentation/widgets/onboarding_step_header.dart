import 'package:flutter/material.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

class OnboardingStepHeader extends StatelessWidget {
  const OnboardingStepHeader({super.key, required this.step, required this.total, required this.title, this.subtitle});
  final int step;
  final int total;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const FulusBrandLogo(size: 36, backgroundColor: Colors.white),
        const Spacer(),
        Text('SETUP  $step/$total', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w800, letterSpacing: .7)),
      ]),
      const SizedBox(height: AppSpacing.sm),
      ClipRRect(borderRadius: BorderRadius.circular(AppRadius.pill), child: LinearProgressIndicator(value: (step / total).clamp(0.0, 1.0), minHeight: 5, backgroundColor: AppColors.borderOf(context))),
      const SizedBox(height: AppSpacing.md),
      Text(title, style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[const SizedBox(height: AppSpacing.xs), Text(subtitle!, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)))],
    ]),
  );
}