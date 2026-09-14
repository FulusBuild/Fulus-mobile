import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

class GetStartedScreen extends ConsumerWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: FulusBrandLogo(
                      size: 72,
                      padding: 10,
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Run your business. Simply.',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Sales, stock, and money — ready when you are, even without internet.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FulusButton(
                    label: 'Create my business',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => ref.read(routerProvider).pushNamed('ownerSetup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
