import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';

const _kExpenseCategories = ['Rent', 'Utilities', 'Transport', 'Wages', 'Other'];
const _kExpensePaymentMethods = ['Cash', 'Mobile Money', 'Bank/Card'];

/// Volume 8's Add Expense screen, field-for-field — Amount, a Category
/// chip row (Rent/Utilities/Transport/Wages/Other), and a "Paid with"
/// chip row, which the Bible flags directly as more than a formality:
/// it's what keeps Daily Closing's cash math honest, since only a
/// Cash-tagged expense reduces the drawer's Expected figure.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _category;
  String? _paymentMethod;
  String? _amountError;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parsedAmount() => double.tryParse(_amountController.text.replaceAll(',', '').trim());

  Future<void> _submit() async {
    final amount = _parsedAmount();
    setState(() {
      _amountError = amount == null || amount <= 0 ? "Amount can't be ₦0" : null;
    });
    if (_amountError != null || _category == null || _paymentMethod == null) {
      if (_category == null || _paymentMethod == null) {
        showFulusSnackbar(context, message: 'Choose a category and how it was paid.');
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(moneyRepositoryProvider).recordExpense(
            amount: amount!,
            category: _category!,
            paymentMethod: _paymentMethod!,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Expense recorded.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFulusSnackbar(context, message: "Couldn't record this expense. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Add expense',
      body: ListView(
        children: [
          FulusTextField(
            label: 'Amount',
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hintText: '0.00',
            errorText: _amountError,
            suffixIcon: const Padding(
              padding: EdgeInsets.only(right: AppSpacing.lg),
              child: Align(widthFactor: 1, child: Text('₦')),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Category', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final category in _kExpenseCategories)
                FulusChip(
                  label: category,
                  selected: _category == category,
                  onTap: () => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Paid with', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final method in _kExpensePaymentMethods)
                FulusChip(
                  label: method,
                  selected: _paymentMethod == method,
                  onTap: () => setState(() => _paymentMethod = method),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusTextField(
            label: 'Note (optional)',
            controller: _noteController,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Save expense',
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}
