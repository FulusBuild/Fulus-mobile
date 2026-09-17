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

typedef _PaymentMethodOption = ({String key, String label});

const _paymentMethods = <_PaymentMethodOption>[
  (key: 'cash', label: 'Cash'),
  (key: 'mobile_money', label: 'Transfer'),
  (key: 'card', label: 'Card'),
  (key: 'credit', label: 'Credit'),
];

IconData _iconForMethod(String key) => switch (key) {
      'cash' => FulusIcons.payments,
      'mobile_money' => FulusIcons.accountBalance,
      'card' => FulusIcons.creditCard,
      'credit' => FulusIcons.receipt,
      _ => FulusIcons.payment,
    };

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
        final splitActive = _splitPayment || cartState.payments.isNotEmpty;
        final oneTap = !canComplete &&
            !splitActive &&
            _method != 'credit' &&
            cartState.payments.isEmpty &&
            enteredAmount != null &&
            enteredAmount >= cartState.remaining - 0.004;

        return FulusScreen(
          title: 'Payment',
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final contentWidth = wide ? 720.0 : double.infinity;

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: AppSpacing.xl,
                      left: wide ? 0 : fulusHorizontalInset(context),
                      right: wide ? 0 : fulusHorizontalInset(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AmountDueHeader(state: cartState),
                        const SizedBox(height: AppSpacing.xl),
                        _SectionLabel(
                          title: splitActive ? 'Split payment' : 'Payment method',
                          subtitle: splitActive ? 'Choose how to pay the remaining balance.' : null,
                        ),
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
                                  onTap: () {
                                    FulusHaptics.selection();
                                    setState(() => _method = method.key);
                                  },
                                ),
                              ),
                        if (splitActive)
                          _SplitMethodWrap(
                            methods: _paymentMethods.where((m) => m.key != 'credit' || creditEnabled).toList(),
                            selected: _method,
                            onSelected: (method) {
                              FulusHaptics.selection();
                              setState(() => _method = method);
                            },
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
                          FulusCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Amount received',
                                  style: AppTypography.label.copyWith(color: AppColors.textSecondaryOf(context)),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                FulusTextField(
                                  label: 'Amount',
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
                            ),
                          ),
                        ],
                        if (cartState.payments.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _SectionLabel(title: 'Payments recorded'),
                          const SizedBox(height: AppSpacing.sm),
                          FulusCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < cartState.payments.length; i++) ...[
                                  FulusListRow(
                                    leading: Icon(
                                      _iconForMethod(cartState.payments[i].method),
                                      color: AppColors.primaryOf(context),
                                    ),
                                    title: Text(_labelFor(cartState.payments[i].method)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          formatMoney(cartState.payments[i].amount, symbol: cartState.currencySymbol),
                                          style: AppTypography.body.copyWith(
                                            color: AppColors.textPrimaryOf(context),
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        FulusIconButton(
                                          icon: FulusIcons.close,
                                          tooltip: 'Remove payment',
                                          onPressed: () {
                                            FulusHaptics.selection();
                                            context.read<CartCubit>().removePayment(cartState.payments[i].localId);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (i < cartState.payments.length - 1)
                                    Divider(height: 1, color: AppColors.borderOf(context)),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (!splitActive && !canComplete) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                FulusHaptics.selection();
                                setState(() => _splitPayment = true);
                              },
                              icon: FulusIcons.callSplit.icon,
                              label: const Text('Split payment'),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        FulusButton(
                          label: canComplete || oneTap
                              ? 'Complete Sale'
                              : (_method == 'credit' ? 'Put Remaining on Account' : 'Add Payment'),
                          loading: canComplete ? cartState.submitting : _adding,
                          onPressed: canComplete ? () => _completeSale(context) : () => _addPayment(context, cartState),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _labelFor(String key) => _paymentMethods.firstWhere(
        (m) => m.key == key,
        orElse: () => (key: key, label: key),
      ).label;

  Future<void> _addPayment(BuildContext context, CartLoaded state) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      FulusHaptics.error();
      showFulusSnackbar(context, message: 'Enter a valid amount.');
      return;
    }
    if (_method != 'cash' && amount > state.remaining + 0.004) {
      FulusHaptics.error();
      showFulusSnackbar(context, message: 'That amount is more than the remaining balance.');
      return;
    }
    if (_method == 'credit') {
      final customer = state.customer;
      if (customer == null) {
        FulusHaptics.error();
        showFulusSnackbar(context, message: 'Select a customer before using credit.');
        return;
      }
      final overage = checkCreditLimitWarning(
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
              'This would put ${customer.name} ${formatMoney(overage, symbol: state.currencySymbol)} over their ${formatMoney(customer.creditLimit!, symbol: state.currencySymbol)} credit limit. Continue anyway?',
            ),
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
      FulusHaptics.selection();
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
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    } catch (_) {
      FulusHaptics.error();
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
      FulusHaptics.confirm();
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
      FulusHaptics.error();
      if (context.mounted) {
        showFulusSnackbar(
          context,
          message: "Couldn't complete the sale — nothing was charged. Try again.",
        );
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ],
    );
  }
}

class _SplitMethodWrap extends StatelessWidget {
  const _SplitMethodWrap({required this.methods, required this.selected, required this.onSelected});

  final List<_PaymentMethodOption> methods;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final method in methods)
          FulusChip(
            label: method.label,
            selected: selected == method.key,
            onTap: () => onSelected(method.key),
          ),
      ],
    );
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
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ),
              Icon(FulusIcons.lock, size: AppIconSize.compact, color: AppColors.textSecondaryOf(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(state.total, symbol: state.currencySymbol),
              style: AppTypography.display.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.amountPaid > 0)
            _PaymentRow(label: 'Paid so far', value: state.amountPaid, symbol: state.currencySymbol),
          _PaymentRow(
            label: 'Remaining',
            value: remaining,
            symbol: state.currencySymbol,
            emphasized: remaining > 0,
          ),
          if (changeDue > 0.004)
            _PaymentRow(
              label: 'Change due',
              value: changeDue,
              symbol: state.currencySymbol,
              emphasized: true,
            ),
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
            child: Text(
              formatMoney(value, symbol: symbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: (emphasized ? AppTypography.subheading : AppTypography.body).copyWith(
                color: emphasized ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
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
    return FulusPressable(
      semanticsLabel: '$label payment method',
      onPressed: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedTintOf(context) : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? primary.withValues(alpha: 0.7) : AppColors.borderOf(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? primary.withValues(alpha: 0.10) : AppColors.surfaceAltOf(context),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                icon,
                size: AppIconSize.base,
                color: selected ? primary : AppColors.textSecondaryOf(context),
              ),
            ),
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
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: selected
                  ? Icon(FulusIcons.check, key: const ValueKey('selected'), size: AppIconSize.compact, color: primary)
                  : const SizedBox(key: ValueKey('unselected'), width: AppIconSize.compact),
            ),
          ],
        ),
      ),
    );
  }
}
