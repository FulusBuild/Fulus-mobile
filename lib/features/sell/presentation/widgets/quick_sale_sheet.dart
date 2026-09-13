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
  String? _nameError;
  String? _priceError;
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
        FulusTextField(
          label: 'What are you selling?',
          controller: _nameController,
          errorText: _nameError,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        FulusTextField(
          label: 'Price',
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: _priceError,
          onChanged: (_) {
            if (_priceError != null) setState(() => _priceError = null);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusButton(label: 'Add to Cart', loading: _saving, onPressed: _submit),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final nameError = name.isEmpty ? 'Enter what you\'re selling.' : null;
    final priceError = price == null || price <= 0 ? 'Enter a price greater than 0.' : null;

    if (nameError != null || priceError != null) {
      setState(() {
        _nameError = nameError;
        _priceError = priceError;
      });
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
      _priceError = null;
    });
    try {
      await context.read<CartCubit>().addQuickSaleItem(description: name, unitPrice: price!);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _priceError = "Couldn't add that item.";
        });
      }
    }
  }
}
