import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/draft_cart.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import '../widgets/customer_picker_sheet.dart';
import 'payment_screen.dart';

/// Volume 5's "The Cart" — review, adjust quantity, optionally attach a
/// customer, then proceed to payment. Reads the same [CartCubit]
/// `SellScreen` created (this screen is pushed onto the Sell branch's
/// own Navigator, which sits beneath that `BlocProvider`, so no second
/// provider is needed here).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, cartState) {
        if (cartState is CartFailure) {
          return FulusScreen(title: 'Cart', body: FulusErrorState(message: cartState.message));
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
              icon: Icons.shopping_cart_outlined,
              actionLabel: 'Back to Sell',
              onAction: () => Navigator.of(context).pop(),
            ),
          );
        }
        return FulusScreen(
          title: 'Cart',
          applyPadding: false,
          body: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: cartState.items.length,
                  separatorBuilder: (context, i) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _CartLineTile(
                    key: ValueKey(cartState.items[i].localId),
                    item: cartState.items[i],
                    currencySymbol: cartState.currencySymbol,
                    unit: cartState.items[i].productLocalId == null
                        ? null
                        : cartState.catalog[cartState.items[i].productLocalId]?.product.unit,
                  ),
                ),
              ),
              _CustomerRow(customer: cartState.customer),
              _TotalsFooter(state: cartState),
            ],
          ),
        );
      },
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
        child: Icon(Icons.delete_outline, color: AppColors.errorOnOf(context)),
      ),
      onDismissed: (_) => _remove(context),
      child: FulusCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.description,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$currencySymbol${item.unitPrice.toStringAsFixed(2)} each',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            _QuantityStepper(item: item, unit: unit),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 72,
              child: Text(
                '$currencySymbol${item.lineTotal.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _remove(BuildContext context) {
    final cubit = context.read<CartCubit>();
    cubit.removeItem(item.localId);
    showFulusSnackbar(
      context,
      message: 'Removed ${item.description}',
      actionLabel: 'Undo',
      onAction: () => cubit.restoreItem(item),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          onTap: () => cubit.decrementItem(item),
        ),
        InkWell(
          onTap: () => _editQuantity(context, cubit),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.quantity}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (unit != null)
                  Text(unit!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          onTap: () => _increment(context, cubit),
        ),
      ],
    );
  }

  Future<void> _increment(BuildContext context, CartCubit cubit) async {
    try {
      await cubit.incrementItem(item);
    } on StateError catch (e) {
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  Future<void> _editQuantity(BuildContext context, CartCubit cubit) async {
    final controller = TextEditingController(text: '${item.quantity}');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quantity'),
        content: FulusTextField(
          label: 'Quantity',
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FulusButton(
            label: 'Update',
            onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(controller.text.trim())),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await cubit.setItemQuantity(item, result);
    } on StateError catch (e) {
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceAltOf(context),
          shape: BoxShape.circle,
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: FulusListRow(
        leading: Icon(Icons.person_outline, color: AppColors.textSecondaryOf(context)),
        title: Text(customer?.name ?? 'Add a customer (optional)'),
        subtitle: customer?.phone == null ? null : Text(customer!.phone!),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => CustomerPickerSheet.show(context),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          boxShadow: AppElevation.liftOf(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TotalRow(label: 'Subtotal', value: state.subtotal, currencySymbol: state.currencySymbol),
            if (state.draftCart.tax > 0)
              _TotalRow(label: 'Tax', value: state.draftCart.tax, currencySymbol: state.currencySymbol),
            const SizedBox(height: AppSpacing.xs),
            _TotalRow(
              label: 'Total',
              value: state.total,
              currencySymbol: state.currencySymbol,
              emphasized: true,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Proceed to Payment',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaymentScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.currencySymbol,
    this.emphasized = false,
  });

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
          Text('$currencySymbol${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
