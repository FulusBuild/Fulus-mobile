import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/business_engine/customer_credit_engine.dart';
import '../../../../core/money/money.dart';
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

@visibleForTesting
bool isPaymentSplitActive({
  required bool explicitlySplit,
  required int paymentCount,
  required double remaining,
}) => explicitlySplit || (paymentCount > 0 && remaining > 0.004);

IconData _iconForMethod(String key) => switch (key) {
      'cash' => FulusIcons.cash,
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
          return const FulusScreen(title: 'Payment', body: _PaymentLoadingSkeleton());
        }

        _syncAmountDefault(moneyToMajor(cartState.remaining));
        final creditEnabled = cartState.customer != null;
        final canComplete = cartState.items.isNotEmpty && cartState.remaining.abs() <= 0.004;
        final enteredAmount = double.tryParse(_amountController.text.trim());
        final splitActive = isPaymentSplitActive(
          explicitlySplit: _splitPayment,
          paymentCount: cartState.payments.length,
          remaining: moneyToMajor(cartState.remaining),
        );
        final oneTap = !canComplete &&
            !splitActive &&
            _method != 'credit' &&
            cartState.payments.isEmpty &&
            enteredAmount != null &&
            enteredAmount >= moneyToMajor(cartState.remaining) - 0.004;

        return FulusScreen(
          title: 'Payment',
          backgroundColor: AppColors.backgroundOf(context),
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
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 1.45,
                            children: [
                              for (final method in _paymentMethods)
                                if (method.key != 'credit' || creditEnabled)
                                  _PaymentMethodTile(
                                    icon: _iconForMethod(method.key),
                                    label: method.label,
                                    selected: _method == method.key,
                                    onTap: () {
                                      FulusHaptics.selection();
                                      setState(() => _method = method.key);
                                    },
                                  ),
                            ],
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
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: AppColors.borderOf(context)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Amount received',
                                  style: AppTypography.label.copyWith(color: Colors.white70, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    AppSpacing.sm,
                                    AppSpacing.md,
                                    AppSpacing.md,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceOf(context),
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Amount',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textSecondaryLight,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      TextField(
                                        controller: _amountController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: AppTypography.subheading.copyWith(
                                          color: AppColors.textPrimaryLight,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  _method == 'cash'
                                      ? 'Enter the cash received. Paying more than the balance shows the change due.'
                                      : 'Enter the amount paid. The remaining balance updates after each payment.',
                                  style: AppTypography.caption.copyWith(color: Colors.white70),
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
                          const SizedBox(height: AppSpacing.md),
                          FulusActionTile(
                            icon: FulusIcons.callSplit,
                            label: 'Split payment',
                            subtitle: 'Use more than one payment method',
                            onTap: () {
                              FulusHaptics.selection();
                              setState(() => _splitPayment = true);
                            },
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
    if (_method != 'cash' && amount > moneyToMajor(state.remaining) + 0.004) {
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
        proposedAdditionalCredit: moneyFromMajor(amount),
        creditLimit: customer.creditLimit,
      );
      if (overage != null && context.mounted) {
        final proceed = await showFulusConfirmDialog(
          context,
          title: 'Over credit limit',
          message:
              'This would put ${customer.name} ${formatMoney(overage, symbol: state.currencySymbol)} over their ${formatMoney(customer.creditLimit!, symbol: state.currencySymbol)} credit limit. Continue anyway?',
          confirmLabel: 'Continue',
          cancelLabel: 'Cancel',
        );
        if (proceed != true || !context.mounted) return;
      }
    }

    setState(() => _adding = true);
    try {
      await context.read<CartCubit>().addPayment(_method, amount);
      _amountSyncedForRemaining = null;
      FulusHaptics.selection();
      if (!context.mounted) return;
      final after = context.read<CartCubit>().state;
      if (after is CartLoaded && after.remaining <= 0.004) {
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
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => SaleSuccessScreen(
            saleId: sale.localId,
            changeDue: moneyToMajor(sale.changeDue),
            currencySymbol: currencySymbol,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
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
          style: AppTypography.subheading.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
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
    final remaining = state.remaining > 0 ? state.remaining : 0;
    final changeDue = state.remaining < 0 ? -state.remaining : 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1473E6),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: AppTypography.caption.copyWith(color: Colors.white70),
                ),
              ),
              Icon(FulusIcons.lock, size: AppIconSize.compact, color: Colors.white70),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(state.total, symbol: state.currencySymbol),
              style: AppTypography.display.copyWith(
                color: Colors.white,
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
          if (changeDue > 0)
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
  final Money value;
  final String symbol;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: Colors.white70)),
          Flexible(
            child: Text(
              formatMoney(value, symbol: symbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: (emphasized ? AppTypography.subheading : AppTypography.body).copyWith(
                color: Colors.white,
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
    final color = switch (label) {
      'Cash' => const Color(0xFF0BBE6E),
      'Transfer' => const Color(0xFF7B3FF2),
      'Card' => const Color(0xFF1473E6),
      _ => const Color(0xFFFF8A00),
    };
    final foreground = AppColors.onColor(color);
    return FulusPressable(
      semanticsLabel: '$label payment method',
      onPressed: onTap,
      child: AnimatedContainer(
        duration: fulusMotionDuration(context, AppMotion.fast),
        constraints: const BoxConstraints(minHeight: 154),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? foreground : Colors.transparent, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: .16), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: FulusPaymentMethodCardColumn(
          icon: icon,
          iconColor: foreground,
          label: label,
          selected: selected,
          selectedMark: Icon(FulusIcons.check, size: AppIconSize.compact, color: foreground),
        ),
      ),
    );
  }
}



class _PaymentLoadingSkeleton extends StatelessWidget {
  const _PaymentLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.xxl),
      children: const [
        FulusSkeletonBox(height: 92, borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg))),
        SizedBox(height: AppSpacing.xl),
        FulusSkeletonBox(width: 140, height: 18),
        SizedBox(height: AppSpacing.sm),
        FulusCardSkeleton(),
        FulusCardSkeleton(),
        SizedBox(height: AppSpacing.lg),
        FulusSkeletonBox(height: 64, borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
      ],
    );
  }
}
