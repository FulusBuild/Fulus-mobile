import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/business_engine/customer_credit_engine.dart';
import '../../../../core/theme/design_tokens.dart';
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

/// Volume 5's "Checkout & Payment" — method selection (Credit only once
/// a customer is attached, per the Bible's exact ordering), an amount
/// that defaults to whatever's still owed, and a running "remaining"
/// figure the sale can't complete until it reaches zero — including the
/// split-payment case the Bible names explicitly ("each amount entered
/// reduces a visible 'remaining' figure").
///
/// Card and Mobile Money each require a live connection before a leg is
/// recorded (Decision 17: "the app says so honestly" rather than
/// letting a cashier believe an unauthorized payment went through) —
/// `connectivity_plus` is already a pubspec dependency (used by
/// `sync_triggers.dart`); this is a second, independent, narrowly-scoped
/// check, not a new dependency or a change to sync's own use of it.
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
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final method in _paymentMethods)
                      if (method.key != 'credit' || creditEnabled)
                        FulusChip(
                          label: method.label,
                          selected: _method == method.key,
                          onTap: () => setState(() => _method = method.key),
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
                            '${cartState.currencySymbol}${payment.amount.toStringAsFixed(2)}',
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
                  label: canComplete
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
    if (_method == 'card' || _method == 'mobile_money') {
      final results = await Connectivity().checkConnectivity();
      if (!context.mounted) return;
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) {
        showFulusSnackbar(
          context,
          message: 'Needs a connection to confirm — try Cash or Credit, or wait for signal.',
        );
        return;
      }
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
              '${state.currencySymbol}${overage.toStringAsFixed(2)} over their '
              '${state.currencySymbol}${customer.creditLimit!.toStringAsFixed(2)} credit limit. '
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
    setState(() => _adding = true);
    try {
      await context.read<CartCubit>().addPayment(_method, amount);
      // Force the amount field to resync against the new remaining
      // figure on the next build, rather than keep showing what's now
      // a stale default.
      _amountSyncedForRemaining = null;
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
          Text('$currencySymbol${value.toStringAsFixed(2)}', style: valueStyle),
        ],
      ),
    );
  }
}
