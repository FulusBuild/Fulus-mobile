import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../onboarding/presentation/screens/transaction_verification_screen.dart';
import '../widgets/receipt_preview_sheet.dart';

/// The sale is already committed before this screen appears. This screen
/// confirms the result, keeps receipt actions close at hand, and makes the
/// ordinary repeat-sale path return directly to Sell rather than dumping the
/// cashier at the app root.
class SaleSuccessScreen extends ConsumerStatefulWidget {
  const SaleSuccessScreen({
    super.key,
    required this.saleId,
    this.changeDue = 0.0,
    this.currencySymbol = '₦',
  });

  final String saleId;
  final double changeDue;
  final String currencySymbol;

  @override
  ConsumerState<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends ConsumerState<SaleSuccessScreen> {
  late final bool _isFirstSale = !ref.read(onboardingStateProvider).hasCelebratedFirstSale;

  @override
  void initState() {
    super.initState();
    if (_isFirstSale) {
      ref.read(onboardingStateProvider).markFirstSaleCelebrated();
    }
  }

  Future<void> _continue(BuildContext context) async {
    if (_isFirstSale) {
      final notifications = ref.read(notificationServiceProvider);
      final proceed = await showFulusPermissionPrimer(
        context,
        icon: Icons.notifications_outlined,
        message:
            "We'll ask to send notifications next — this lets us tell you if a blocked payment finishes going through, or if something needs your attention.",
      );
      if (proceed) await notifications.ensurePermission();
      try {
        final onboardingState = ref.read(onboardingStateProvider);
        if (onboardingState.walkthroughStep == OnboardingStep.firstSale) {
          await onboardingState.recordWalkthroughFirstSale(widget.saleId);
          await onboardingState.advanceWalkthroughTo(OnboardingStep.verification);
          if (context.mounted) {
            ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.verification;
          }
        }
      } catch (_) {
        // The sale is already complete; walkthrough bookkeeping is best effort.
      }
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TransactionVerificationScreen(saleId: widget.saleId)),
      );
      return;
    }

    if (!context.mounted) return;
    context.goNamed('sell');
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sale Complete',
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: AppGradients.successOf(context),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryOf(context),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      color: AppColors.onPrimaryOf(context),
                      size: AppIconSize.emphasis,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _isFirstSale ? "That's your first sale on Fulus." : 'Sale complete',
                    textAlign: TextAlign.center,
                    style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  if (_isFirstSale) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Nice work.',
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                  if (widget.changeDue > 0) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppElevation.cardOf(context),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Change due',
                            style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            formatMoney(widget.changeDue, symbol: widget.currencySymbol),
                            style: AppTypography.heading.copyWith(color: AppColors.primaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            ReceiptPreviewSheet(saleId: widget.saleId),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: _isFirstSale ? 'View what changed' : 'New Sale',
                onPressed: () => _continue(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
