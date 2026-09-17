import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/draft_cart.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import '../widgets/customer_picker_sheet.dart';
import '../widgets/discount_sheet.dart';
import 'payment_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, cartState) {
        if (cartState is CartFailure) {
          return FulusScreen(
            title: 'Cart',
            body: FulusErrorState(
              message: cartState.message,
              onRetry: () => context.read<CartCubit>().retryInitialization(),
            ),
          );
        }
        if (cartState is! CartLoaded) {
          return const FulusScreen(title: 'Cart', body: FulusLoadingIndicator());
        }
        if (cartState.items.isEmpty) {
          return FulusScreen(
            title: 'Cart',
            body: FulusEmptyState(
              headline: 'Your cart is empty',
              body: 'Add a product from Sell to start a sale.',
              icon: FulusIcons.shoppingCart,
              actionLabel: 'Back to Sell',
              onAction: () => Navigator.of(context).pop(),
            ),
          );
        }

        return FulusScreen(
          title: 'Cart',
          applyPadding: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = fulusHorizontalInset(context);
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.md),
                      children: [
                        _CartIntro(itemCount: cartState.items.length),
                        const SizedBox(height: AppSpacing.md),
                        if (wide)
                          _WideCartList(state: cartState)
                        else
                          _CompactCartList(state: cartState),
                        const SizedBox(height: AppSpacing.sm),
                        _CustomerRow(customer: cartState.customer),
                      ],
                    ),
                  ),
                  _TotalsFooter(state: cartState),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _CartIntro extends StatelessWidget {
  const _CartIntro({required this.itemCount});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        Text(
          'Swipe left to remove',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
        ),
      ],
    );
  }
}

class _CompactCartList extends StatelessWidget {
  const _CompactCartList({required this.state});
  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < state.items.length; i++) ...[
          _CartLineTile(
            key: ValueKey(state.items[i].localId),
            item: state.items[i],
            currencySymbol: state.currencySymbol,
            unit: state.items[i].productLocalId == null
                ? null
                : state.catalog[state.items[i].productLocalId]?.product.unit,
          ),
          if (i < state.items.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _WideCartList extends StatelessWidget {
  const _WideCartList({required this.state});
  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < state.items.length; i++) ...[
            _CartLineTile(
              key: ValueKey(state.items[i].localId),
              item: state.items[i],
              currencySymbol: state.currencySymbol,
              unit: state.items[i].productLocalId == null
                  ? null
                  : state.catalog[state.items[i].productLocalId]?.product.unit,
            ),
            if (i < state.items.length - 1) Divider(height: 1, color: AppColors.borderOf(context)),
          ],
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({super.key, required this.item, required this.currencySymbol, this.unit});

  final DraftCartItem item;
  final String currencySymbol;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismissible-${item.localId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.errorOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(FulusIcons.delete, color: AppColors.errorOnOf(context)),
      ),
      onDismissed: (_) => _remove(context),
      child: FulusCard(
        onTap: () => _editDiscount(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 390;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.lineDiscount > 0
                            ? '${formatMoney(item.unitPrice, symbol: currencySymbol)} each · ${formatMoney(item.lineDiscount, symbol: currencySymbol)} off'
                            : '${formatMoney(item.unitPrice, symbol: currencySymbol)} each',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: item.lineDiscount > 0
                              ? AppColors.primaryOf(context)
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (!compact) ...[
                  _QuantityStepper(item: item, unit: unit),
                  const SizedBox(width: AppSpacing.sm),
                ] else
                  _CompactQuantity(item: item, unit: unit),
                SizedBox(
                  width: compact ? 76 : 92,
                  child: Text(
                    formatMoney(item.lineTotal - item.lineDiscount, symbol: currencySymbol),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editDiscount(BuildContext context) async {
    final cubit = context.read<CartCubit>();
    final state = cubit.state;
    await DiscountSheet.show(
      context,
      title: 'Discount on ${item.description}',
      baseAmount: item.lineTotal,
      currencySymbol: state is CartLoaded ? state.currencySymbol : '',
      initialDiscount: item.lineDiscount,
      onSave: (amount) => cubit.updateItemDiscount(item, amount),
    );
  }

  void _remove(BuildContext context) {
    final cubit = context.read<CartCubit>();
    cubit.removeItem(item.localId);
    FulusHaptics.selection();
    showFulusSnackbar(
      context,
      message: 'Removed ${item.description}',
      actionLabel: 'Undo',
      onAction: () => cubit.restoreItem(item),
    );
  }
}

class _CompactQuantity extends StatelessWidget {
  const _CompactQuantity({required this.item, this.unit});
  final DraftCartItem item;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAltOf(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        unit == null ? '×${item.quantity}' : '×${item.quantity} $unit',
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(color: AppColors.textPrimaryOf(context)),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.item, this.unit});

  final DraftCartItem item;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CartCubit>();
    return Container(
      height: AppTouchTarget.minimum,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceAltOf(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(icon: FulusIcons.remove, semanticsLabel: 'Decrease ${item.description}', onTap: () => cubit.decrementItem(item)),
          FulusPressable(
            semanticsLabel: 'Edit quantity for ${item.description}',
            onPressed: () => _editQuantity(context, cubit),
            child: SizedBox(
              height: AppTouchTarget.minimum,
              width: 46,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item.quantity}', style: AppTypography.label.copyWith(color: AppColors.textPrimaryOf(context))),
                  if (unit != null) Text(unit!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
          ),
          _StepButton(icon: FulusIcons.add, semanticsLabel: 'Increase ${item.description}', onTap: () => _increment(context, cubit)),
        ],
      ),
    );
  }

  Future<void> _increment(BuildContext context, CartCubit cubit) async {
    try {
      await cubit.incrementItem(item);
      FulusHaptics.selection();
    } on StateError catch (e) {
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  Future<void> _editQuantity(BuildContext context, CartCubit cubit) async {
    final controller = TextEditingController(text: '${item.quantity}');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quantity'),
        scrollable: true,
        content: FulusTextField(label: 'Quantity', controller: controller, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FulusButton(label: 'Update', onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(controller.text.trim()))),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    try {
      await cubit.setItemQuantity(item, result);
      FulusHaptics.selection();
    } on StateError catch (e) {
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.semanticsLabel});
  final IconData icon;
  final VoidCallback onTap;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return FulusPressable(
      semanticsLabel: semanticsLabel,
      onPressed: onTap,
      child: SizedBox(
        width: AppTouchTarget.minimum - 4,
        height: AppTouchTarget.minimum,
        child: Icon(icon, size: AppIconSize.compact, color: AppColors.textPrimaryOf(context)),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});
  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      onTap: () => CustomerPickerSheet.show(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selectedTintOf(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(FulusIcons.person, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.name ?? 'Add a customer',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  customer?.phone ?? 'Optional for this sale',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          Icon(FulusIcons.chevronRight, color: AppColors.textSecondaryOf(context)),
        ],
      ),
    );
  }
}

class _TotalsFooter extends StatelessWidget {
  const _TotalsFooter({required this.state});
  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          fulusHorizontalInset(context),
          AppSpacing.md,
          fulusHorizontalInset(context),
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          boxShadow: AppElevation.liftOf(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TotalRow(label: 'Subtotal', value: state.subtotal, currencySymbol: state.currencySymbol),
            _DiscountRow(state: state),
            if (state.draftCart.tax > 0)
              _TotalRow(label: 'Tax', value: state.draftCart.tax, currencySymbol: state.currencySymbol),
            const SizedBox(height: AppSpacing.xs),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: AppSpacing.sm),
            _TotalRow(label: 'Total', value: state.total, currencySymbol: state.currencySymbol, emphasized: true),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Continue to payment · ${formatMoney(state.total, symbol: state.currencySymbol)}',
                onPressed: () {
                  final cubit = context.read<CartCubit>();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(value: cubit, child: const PaymentScreen()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscountRow extends StatelessWidget {
  const _DiscountRow({required this.state});
  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = state.discount > 0;
    return FulusPressable(
      semanticsLabel: 'Discount for this sale',
      onPressed: () => DiscountSheet.show(
        context,
        title: 'Discount on this sale',
        baseAmount: state.subtotal,
        currencySymbol: state.currencySymbol,
        initialDiscount: state.draftCart.wholeCartDiscount,
        onSave: (amount) => context.read<CartCubit>().setWholeCartDiscount(amount),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Discount', style: AppTypography.body.copyWith(color: AppColors.primaryOf(context))),
            Flexible(
              child: Text(
                hasDiscount ? '-${formatMoney(state.discount, symbol: state.currencySymbol)}' : 'Add',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.body.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, required this.currencySymbol, this.emphasized = false});

  final String label;
  final double value;
  final String currencySymbol;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))
        : AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Flexible(
            child: Text(
              formatMoney(value, symbol: currencySymbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}
