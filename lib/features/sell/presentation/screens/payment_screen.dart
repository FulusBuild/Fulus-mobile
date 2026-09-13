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

// Payment is optimized for the common case: see the total, choose a method,
// and finish. Split payments are an explicit escape hatch and then remain
// visible as the active mode until the balance is settled.
typedef _PaymentMethodOption = ({String key, String label});

const _paymentMethods = <_PaymentMethodOption>[
  (key: 'cash', label: 'Cash'),
  (key: 'mobile_money', label: 'Transfer'),
  (key: 'card', label: 'Card'),
  (key: 'credit', label: 'Credit'),
];

IconData _iconForMethod(String key) {
  switch (key) {
    case 'cash': return Icons.payments_outlined;
    case 'mobile_money': return Icons.account_balance_outlined;
    case 'card': return Icons.credit_card_outlined;
    case 'credit': return Icons.receipt_long_outlined;
    default: return Icons.payment_outlined;
  }
}

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
  bool _splitPayment = false;

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
        final canComplete = cartState.items.isNotEmpty && cartState.remaining.abs() <= 0.004;
        final enteredAmount = double.tryParse(_amountController.text.trim());
        final willCompleteInOneTap = !canComplete &&
            !_splitPayment &&
            _method != 'credit' &&
            cartState.payments.isEmpty &&
            enteredAmount != null &&
            enteredAmount >= cartState.remaining - 0.004;
        final splitActive = _splitPayment || cartState.payments.isNotEmpty;

        return FulusScreen(
          title: 'Payment',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AmountDueHeader(state: cartState),
                const SizedBox(height: AppSpacing.xl),
                Text(splitActive ? 'Split payment' : 'Payment method', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.sm),
                if (!splitActive)
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
                if (splitActive) ...[
                  Text('Choose how to pay the remaining amount.', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final method in _paymentMethods)
                        if (method.key != 'credit' || creditEnabled)
                          ChoiceChip(
                            label: Text(method.label),
                            avatar: Icon(_iconForMethod(method.key), size: AppIconSize.compact),
                            selected: _method == method.key,
                            onSelected: (_) => setState(() => _method = method.key),
                          ),
                    ],
                  ),
                ],
                if (!creditEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text('Select a customer in Cart to sell on credit.', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                  ),
                if (!canComplete) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FulusTextField(
                    label: 'Amount received',
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _method == 'cash'
                        ? 'Enter the cash received. Paying more than the balance shows the change due.'
                        : 'Enter the amount paid. The remaining balance updates after each payment.',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
                if (cartState.payments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Payments recorded', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                  for (final payment in cartState.payments)
                    FulusListRow(
                      title: Text(_labelFor(payment.method)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatMoney(payment.amount, symbol: cartState.currencySymbol), style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove payment',
                            onPressed: () => context.read<CartCubit>().removePayment(payment.localId),
                          ),
                        ],
                      ),
                    ),
                ],
                if (!splitActive && !canComplete) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextButton.icon(
                    onPressed: () => setState(() => _splitPayment = true),
                    icon: const Icon(Icons.call_split_outlined),
                    label: const Text('Split payment'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: canComplete || willCompleteInOneTap
                      ? 'Complete Sale'
                      : (_method == 'credit' ? 'Put Remaining on Account' : 'Add Payment'),
                  loading: canComplete ? cartState.submitting : _adding,
                  onPressed: canComplete ? () => _completeSale(context) : () => _addPayment(context, cartState),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }

  String _labelFor(String key) => _paymentMethods.firstWhere((m) => m.key == key, orElse: () => (key: key, label: key)).label;

  Future<void> _addPayment(BuildContext context, CartLoaded state) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showFulusSnackbar(context, message: 'Enter a valid amount.');
      return;
    }
    if (_method != 'cash' && amount > state.remaining + 0.004) {
      showFulusSnackbar(context, message: 'That amount is more than the remaining balance.');
      return;
    }
    if (_method == 'credit') {
      final customer = state.customer;
      if (customer == null) {
        showFulusSnackbar(context, message: 'Select a customer before using credit.');
        return;
      }
      final overage = checkCreditLimitWarning(currentBalance: customer.outstandingBalance, proposedAdditionalCredit: amount, creditLimit: customer.creditLimit);
      if (overage != null && context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Over credit limit'),
            content: Text('This would put ${customer.name} ${formatMoney(overage, symbol: state.currencySymbol)} over their ${formatMoney(customer.creditLimit!, symbol: state.currencySymbol)} credit limit. Continue anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Continue')),
            ],
          ),
        );
        if (proceed != true || !context.mounted) return;
      }
    }
    final wasFirstPayment = state.payments.isEmpty;
    setState(() => _adding = true);
    try {
      await context.read<CartCubit>().addPayment(_method, amount);
      _amountSyncedForRemaining = null;
      if (!context.mounted) return;
      final after = context.read<CartCubit>().state;
      if (wasFirstPayment && after is CartLoaded && after.remaining <= 0.004) {
        await _completeSale(context);
        return;
      }
      if (after is CartLoaded && after.remaining > 0.004) {
        setState(() => _splitPayment = true);
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
      if (context.mounted) ProviderScope.containerOf(context, listen: false).read(dataRefreshSignalProvider.notifier).state++;
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleSuccessScreen(saleId: sale.localId, changeDue: sale.changeDue, currencySymbol: currencySymbol)));
    } catch (_) {
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't complete the sale — nothing was charged. Try again.");
    }
  }
}

class _AmountDueHeader extends StatelessWidget {
  const _AmountDueHeader({required this.state});
  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    final remaining = state.remaining > 0 ? state.remaining : 0.0;
    final changeDue = state.remaining < 0 ? -state.remaining : 0.0;
    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Total', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: AppSpacing.xs),
          Text(formatMoney(state.total, symbol: state.currencySymbol), style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: AppSpacing.lg),
          if (state.amountPaid > 0) _PaymentRow(label: 'Paid so far', value: state.amountPaid, symbol: state.currencySymbol),
          _PaymentRow(label: 'Remaining', value: remaining, symbol: state.currencySymbol, emphasized: remaining > 0),
          if (changeDue > 0.004) _PaymentRow(label: 'Change due', value: changeDue, symbol: state.currencySymbol, emphasized: true),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.label, required this.value, required this.symbol, this.emphasized = false});
  final String label;
  final double value;
  final String symbol;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          Flexible(
            child: Text(formatMoney(value, symbol: symbol), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: (emphasized ? AppTypography.subheading : AppTypography.body).copyWith(color: emphasized ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

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
        decoration: BoxDecoration(color: selected ? AppColors.selectedTintOf(context) : AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: selected ? primary : AppColors.borderOf(context))),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.base, color: selected ? primary : AppColors.textSecondaryOf(context)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTypography.body.copyWith(color: selected ? primary : AppColors.textPrimaryOf(context), fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
            if (selected) Icon(Icons.check_circle, size: AppIconSize.compact, color: primary),
          ],
        ),
      ),
    );
  }
}