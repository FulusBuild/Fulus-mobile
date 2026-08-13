import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/receipt_preview_sheet.dart';

/// Volume 5: "The instant payment is confirmed, the sale is done —
/// printing or sharing a receipt is what happens next, not a condition
/// of completion." This screen IS that instant — the sale already
/// exists by the time it's shown — and [ReceiptPreviewSheet] (already
/// built) is the receipt step, reused as-is rather than a second
/// receipt flow invented for this screen.
///
/// Reached via `Navigator.pushReplacement` from `PaymentScreen` (see
/// that screen's own `_completeSale`), so Payment is already gone from
/// the stack by the time this shows — the ordinary system/gesture back
/// action from here lands on Cart, now showing empty (the same
/// completed sale cleared it), not on a stale Payment screen for a sale
/// that's already done. No extra back-button handling needed for that.
class SaleSuccessScreen extends StatelessWidget {
  const SaleSuccessScreen({
    super.key,
    required this.saleId,
    this.changeDue = 0.0,
    this.currencySymbol = '₦',
  });

  final String saleId;

  /// Bug fix (business-logic audit): no "change due" concept existed
  /// anywhere in this app before this — `PaymentScreen`'s cash flow lets
  /// a customer overpay (perfectly normal — handing over a larger note
  /// than the total) with nothing telling the cashier how much to hand
  /// back. Passed in directly from `Sale.changeDue` at the moment the
  /// sale completes in `PaymentScreen._completeSale`, rather than this
  /// screen re-fetching a `Sale` it doesn't otherwise need, just to read
  /// one field back off it.
  final double changeDue;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sale Complete',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppColors.primaryOf(context), size: AppIconSize.hero),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Sale complete',
              style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
            if (changeDue > 0) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryOf(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    Text(
                      'Change due',
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$currencySymbol${changeDue.toStringAsFixed(2)}',
                      style: AppTypography.heading.copyWith(color: AppColors.primaryOf(context)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'View Receipt',
                variant: FulusButtonVariant.secondary,
                icon: Icons.receipt_long_outlined,
                onPressed: () => ReceiptPreviewSheet.show(context, saleId),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'New Sale',
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
