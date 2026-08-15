import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
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
///
/// Nice-to-have gap closure — Volume 3's "Success Celebration": "A
/// short, warm, restrained confirmation... 'That's your first sale on
/// [Fulus]. Nice work.' with the completed receipt shown underneath,
/// and a single next action." [_isFirstSale] decides, once, whether
/// this build shows that variant or the ordinary one every sale after
/// it already shows — see [OnboardingState.hasCelebratedFirstSale]'s
/// doc comment for why the flag this reads defaults to "already
/// celebrated" for every business except one just created in this same
/// session.
///
/// The receipt itself is embedded directly ([ReceiptPreviewSheet] used
/// inline, not behind the "View Receipt" tap it's normally behind) to
/// satisfy "shown underneath" literally — deliberately reusing that
/// widget completely unmodified rather than duplicating its layout or
/// its data-loading `FutureBuilder`, which also means this screen
/// inherits, rather than fixes, that widget's own known rendering gap
/// (raw total, no line items) — a separate, already-flagged piece of
/// work, not something this pass touches.
///
/// Also carries Volume 3's third contextual-permission moment
/// ("Notifications... when they finish their first sale") — primed and
/// requested from [_continue] rather than the instant this screen
/// appears, so the primer dialog doesn't compete with the celebration
/// copy for attention; it fires as the owner is already moving on.
class SaleSuccessScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends ConsumerState<SaleSuccessScreen> {
  // Decided once, from the value as it stood the instant this screen
  // opened — `late final` (not a plain getter) so this screen instance
  // can't flip which variant is showing mid-view on some unrelated
  // rebuild.
  late final bool _isFirstSale = !ref.read(onboardingStateProvider).hasCelebratedFirstSale;

  @override
  void initState() {
    super.initState();
    if (_isFirstSale) {
      // Fire-and-forget, same as ResolveActiveLocation's best-effort
      // calls in OwnerSetupScreen — nothing on this screen depends on
      // the write finishing; a rare failure here just means this
      // one-time moment quietly doesn't repeat, not a broken sale.
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
    }
    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sale Complete',
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Redesign pass — a soft celebratory panel behind the
            // checkmark rather than it floating on plain background;
            // still "restrained" (Volume 3) — a tint, not a full-bleed
            // banner or confetti.
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
                    decoration: BoxDecoration(color: AppColors.primaryOf(context), shape: BoxShape.circle),
                    child: Icon(Icons.check, color: AppColors.onPrimaryOf(context), size: AppIconSize.emphasis),
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
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
            if (_isFirstSale) ...[
              // "the completed receipt shown underneath" — the exact
              // existing widget, unmodified, just not gated behind a
              // tap the way the ordinary "View Receipt" button below
              // gates it.
              ReceiptPreviewSheet(saleId: widget.saleId),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FulusButton(label: 'Continue', onPressed: () => _continue(context)),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FulusButton(
                  label: 'View Receipt',
                  variant: FulusButtonVariant.secondary,
                  icon: Icons.receipt_long_outlined,
                  onPressed: () => ReceiptPreviewSheet.show(context, widget.saleId),
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
          ],
        ),
      ),
    );
  }
}
