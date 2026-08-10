import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';

/// Volume 5: "Quick Sale remains available from Sell at any time for
/// anything not in the catalog at all." Adds straight to the same
/// draft cart every other line goes through
/// ([CartCubit.addQuickSaleItem] → `DraftCartRepository.addItem` with
/// `productLocalId: null`) — no separate quick-sale entity or flow.
class QuickSaleSheet extends StatefulWidget {
  const QuickSaleSheet({super.key});

  static Future<void> show(BuildContext context) {
    final cubit = context.read<CartCubit>();
    return showFulusBottomSheet(
      context: context,
      title: 'Quick Sale',
      builder: (_) => BlocProvider.value(value: cubit, child: const QuickSaleSheet()),
    );
  }

  @override
  State<QuickSaleSheet> createState() => _QuickSaleSheetState();
}

class _QuickSaleSheetState extends State<QuickSaleSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'For anything not in your catalogue yet.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusTextField(label: 'What are you selling?', controller: _nameController),
        const SizedBox(height: AppSpacing.md),
        FulusTextField(
          label: 'Price',
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: _error,
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusButton(label: 'Add to Cart', loading: _saving, onPressed: _submit),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    if (name.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Enter what you\'re selling and a price greater than 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<CartCubit>().addQuickSaleItem(description: name, unitPrice: price);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't add that item.";
        });
      }
    }
  }
}
