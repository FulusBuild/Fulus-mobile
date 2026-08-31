import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/business_engine/customer_credit_engine.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import 'sale_success_screen.dart';

/// One payment method option — a plain record rather than an enum,
/// matching how loosely this small a vocabulary is used everywhere else
/// in the codebase (e.g. `Sale.paymentMethod` itself is a plain
/// `String?`, not an enum — see that field's own doc comment for why:
/// it rides straight through to the backend's own free-text column).
/// The credit-requires-a-customer gate lives inline in [PaymentScreen]
/// (`creditEnabled`), the one place that already has both the method
/// list and the cart's customer to check together.
typedef _PaymentMethodOption = ({String key, String label});

const _paymentMethods = <_PaymentMethodOption>[
  (key: 'cash', label: 'Cash'),
  (key: 'mobile_money', label: 'Mobile Money'),
  (key: 'card', label: 'Card'),
  (key: 'credit', label: 'Credit'),
];

/// Redesign pass — the glyph shown on each [_PaymentMethodTile], purely
/// cosmetic (the `key` string is still what actually drives logic
/// everywhere else on this screen).
IconData _iconForMethod(String key) {
  switch (key) {
    case 'cash':
      return Icons.payments_outlined;
    case 'mobile_money':
      return Icons.phone_android_outlined;
    case 'card':
      return Icons.credit_card_outlined;
    case 'credit':
      return Icons.receipt_long_outlined;
    default:
      return Icons.payment_outlined;
  }
}

/// Volume 5's "Checkout & Payment" — method selection (Credit only once
/// a customer is attached, per the Bible's exact ordering), an amount
/// that defaults to whatever's still owed, and a running "remaining"
/// figure the sale can't complete until it reaches zero — including the
/// split-payment case the Bible names explicitly ("each amount entered
/// reduces a visible 'remaining' figure").
///
/// Decision 17 reversed: Card and Mobile Money no longer require a live
/// connection before a leg is recorded. The original rationale ("the
/// app says so honestly" rather than letting a cashier believe an
/// unauthorized payment went through) assumed this app itself performs
/// some kind of authorization it can honestly confirm or deny — it
/// doesn't. There is no payment-gateway/card-reader integration
/// anywhere in this codebase; selecting Card or Mobile Money is the
/// same manual cashier attestation "I received this" that Cash always
/// was, and the real-world charge (a separate POS terminal, the
/// customer's own mobile-money transfer) happens over a connection this
/// device's own signal has no bearing on. Gating entry on THIS device's
/// connectivity blocked legitimate completed sales for exactly the
/// offline, spotty-signal merchants this app is built for, without
/// actually verifying anything real. Card/Mobile Money now persist
/// through the same local-write-then-sync path as every other payment
/// method (see `_addPayment` below) — no special-casing.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _method = 'cash';
  final _amountController = TextEditingController();
  double? _amountSyncedForRemaining;
  bool _adding = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _syncAmountDefault(double remaining) {
    final clamped = remaining > 0 ? remaining : 0.0;
    if (_amountSyncedForRemaining == clamped) return;
    _amountSyncedForRemaining = clamped;
    _amountController.text = clamped.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, cartState) {
        if (cartState is! CartLoaded) {
          return const FulusScreen(title: 'Payment', body: FulusLoadingIndicator());
        }
        _syncAmountDefault(cartState.remaining);
        final creditEnabled = cartState.customer != null;
        final canComplete = cartState.remaining <= 0.004;
        // UX fix: the overwhelmingly common sale — one payment method,
        // full amount, no split — used to always cost two taps ("Add
        // Payment", then "Complete Sale") even though the amount field
        // is pre-filled with the full remaining balance from the start.
        // When this tap would be the first payment AND it fully covers
        // the total, the button says what it will actually do and
        // _addPayment below completes the sale in the same tap instead
        // of waiting for a second press.
        final enteredAmount = double.tryParse(_amountController.text.trim());
        final willCompleteInOneTap = !canComplete &&
            _method != 'credit' && // 'Put Remaining on Account' already says what it does
            cartState.payments.isEmpty &&
            enteredAmount != null &&
            enteredAmount >= cartState.remaining - 0.004;

        return FulusScreen(
          title: 'Payment',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryCard(state: cartState),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Payment method',
                  style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Column(
                  children: [
                    for (final method in _paymentMethods)
                      if (method.key != 'credit' || creditEnabled)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _PaymentMethodTile(
                            icon: _iconForMethod(method.key),
                            label: method.label,
                            selected: _method == method.key,
                            onTap: () => setState(() => _method = method.key),
                          ),
                        ),
                  ],
                ),
                if (!creditEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Select a customer in Cart to sell on credit.',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                if (!canComplete) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FulusTextField(
                    label: 'Amount',
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                if (cartState.payments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Payments recorded',
                    style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  for (final payment in cartState.payments)
                    FulusListRow(
                      title: Text(_labelFor(payment.method)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMoney(payment.amount, symbol: cartState.currencySymbol),
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimaryOf(context),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove',
                            onPressed: () => context.read<CartCubit>().removePayment(payment.localId),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: canComplete || willCompleteInOneTap
                      ? 'Complete Sale'
                      : (_method == 'credit' ? 'Put Remaining on Account' : 'Add Payment'),
                  loading: canComplete ? cartState.submitting : _adding,
                  onPressed: canComplete
                      ? () => _completeSale(context)
                      : () => _addPayment(context, cartState),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }

  String _labelFor(String key) =>
      _paymentMethods.firstWhere((m) => m.key == key, orElse: () => (key: key, label: key)).label;

  Future<void> _addPayment(BuildContext context, CartLoaded state) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showFulusSnackbar(context, message: 'Enter a valid amount.');
      return;
    }
    // Bug fix (business-logic audit): checkCreditLimitWarning existed
    // specifically for this moment — extending a customer's credit past
    // their own set limit — but had no caller anywhere in the app
    // (confirmed by grep). Informational only, per the function's own
    // doc comment (Decision 23: a limit is "a guide," not an enforced
    // ceiling) — this dialog can always be dismissed and the sale
    // continues either way; it only ever adds a confirmation, never a
    // block.
    if (_method == 'credit') {
      final customer = state.customer;
      final overage = customer == null
          ? null
          : checkCreditLimitWarning(
              currentBalance: customer.outstandingBalance,
              proposedAdditionalCredit: amount,
              creditLimit: customer.creditLimit,
            );
      if (overage != null && context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Over credit limit'),
            content: Text(
              'This would put ${customer!.name} '
              '${formatMoney(overage, symbol: state.currencySymbol)} over their '
              '${formatMoney(customer.creditLimit!, symbol: state.currencySymbol)} credit limit. '
              'Continue anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        if (!context.mounted) return;
      }
    }
    final wasFirstPayment = state.payments.isEmpty;
    setState(() => _adding = true);
    try {
      await context.read<CartCubit>().addPayment(_method, amount);
      // Force the amount field to resync against the new remaining
      // figure on the next build, rather than keep showing what's now
      // a stale default.
      _amountSyncedForRemaining = null;
      // UX fix: a first payment that fully covers the total shouldn't
      // need a second tap to finish the sale — see this screen's
      // `willCompleteInOneTap` for why. Split-payment behavior is
      // unchanged: this only fires when it was the FIRST payment leg,
      // never after a partial payment brings remaining to zero on a
      // later leg, so a cashier deliberately splitting a payment still
      // sees the ordinary review-then-"Complete Sale" step.
      if (!context.mounted) return;
      final after = context.read<CartCubit>().state;
      if (wasFirstPayment && after is CartLoaded && after.remaining <= 0.004) {
        await _completeSale(context);
        return;
      }
    } on StateError catch (e) {
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    } catch (_) {
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't record that payment.");
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _completeSale(BuildContext context) async {
    final cubit = context.read<CartCubit>();
    final state = cubit.state;
    final currencySymbol = state is CartLoaded ? state.currencySymbol : '₦';
    try {
      final sale = await cubit.completeSale();
      // Gap fix: nothing told Home/Money/Reports a sale had happened —
      // see dataRefreshSignalProvider's own doc comment in
      // app/providers.dart. This screen is a plain StatefulWidget (not
      // ConsumerStatefulWidget — CartCubit/flutter_bloc is this
      // feature's own deliberate exception, see this file's own header
      // comment), so this reads the provider via its container directly
      // rather than converting the whole widget just for one bump.
      if (context.mounted) {
        ProviderScope.containerOf(context, listen: false).read(dataRefreshSignalProvider.notifier).state++;
      }
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleSuccessScreen(
            saleId: sale.localId,
            changeDue: sale.changeDue,
            currencySymbol: currencySymbol,
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(
          context,
          message: "Couldn't complete the sale — nothing was charged. Try again.",
        );
      }
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    // Bug fix (business-logic audit): the Remaining row below already
    // clamped `state.remaining` to 0 on overpayment — correct, as
    // "nothing more is owed" — but that clamp also silently threw away
    // the one thing a cashier actually needs to know in that moment:
    // how much change to hand back. PaymentScreen hides its own
    // amount-entry field entirely once `remaining <= 0` (see
    // `canComplete`'s own gate above), so this card is the last place
    // on this screen the cashier sees before tapping Complete Sale.
    final changeDue = state.remaining < 0 ? -state.remaining : 0.0;
    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(label: 'Total', value: state.total, currencySymbol: state.currencySymbol, emphasized: true),
          if (state.amountPaid > 0)
            _Row(label: 'Paid so far', value: state.amountPaid, currencySymbol: state.currencySymbol),
          _Row(
            label: 'Remaining',
            value: state.remaining > 0 ? state.remaining : 0,
            currencySymbol: state.currencySymbol,
            valueColor: state.remaining > 0.004 ? AppColors.warningOf(context) : AppColors.primaryOf(context),
          ),
          if (changeDue > 0.004)
            _Row(
              label: 'Change due',
              value: changeDue,
              currencySymbol: state.currencySymbol,
              valueColor: AppColors.primaryOf(context),
              emphasized: true,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.currencySymbol,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final double value;
  final String currencySymbol;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context));
    final valueStyle = (emphasized ? AppTypography.heading : AppTypography.body).copyWith(
      color: valueColor ?? AppColors.textPrimaryOf(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          // Responsive UI audit — Flexible+ellipsis on the value side.
          Flexible(
            child: Text(
              formatMoney(value, symbol: currencySymbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Redesign pass — a selectable, icon-labeled row standing in for the
/// old [FulusChip]-in-a-[Wrap] layout. One selectable payment method
/// carries more weight than a filter chip (it decides how the sale is
/// recorded, plus gates a live-connectivity check for two of the four
/// options) — a full-width row with its own icon reads as a deliberate
/// choice rather than a tag, and stacks cleanly regardless of label
/// length ("Mobile Money" vs "Cash").
class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: AppTouchTarget.minimum + AppSpacing.sm,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedTintOf(context) : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? primary : AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.base, color: selected ? primary : AppColors.textSecondaryOf(context)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: selected ? primary : AppColors.textPrimaryOf(context),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: AppIconSize.compact, color: primary),
          ],
        ),
      ),
    );
  }
}
