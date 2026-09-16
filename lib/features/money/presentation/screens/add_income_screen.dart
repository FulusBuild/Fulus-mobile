import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';

/// Volume 8's "Add Income" action — money in that wasn't a sale. No
/// dedicated mockup exists for this one (only Add Expense was mocked,
/// per the Bible's own approval note), so this mirrors Add Expense's
/// layout and field order minus the two chip rows a source of income
/// doesn't have a fixed category list for.
class AddIncomeScreen extends ConsumerStatefulWidget {
  const AddIncomeScreen({super.key});

  @override
  ConsumerState<AddIncomeScreen> createState() => _AddIncomeScreenState();
}

class _AddIncomeScreenState extends ConsumerState<AddIncomeScreen> {
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _noteController = TextEditingController();
  String? _amountError;
  String? _sourceError;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parsedAmount() => double.tryParse(_amountController.text.replaceAll(',', '').trim());

  Future<void> _submit() async {
    final amount = _parsedAmount();
    final source = _sourceController.text.trim();
    final currencySymbol = ref.read(moneyCurrencySymbolProvider).value ?? '₦';
    setState(() {
      _amountError = amount == null || amount <= 0 ? "Amount can't be ${currencySymbol}0" : null;
      _sourceError = source.isEmpty ? 'Say what this income was from' : null;
    });
    if (_amountError != null || _sourceError != null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(moneyRepositoryProvider).recordIncome(
            amount: amount!,
            source: source,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      // See dataRefreshSignalProvider's own doc comment in
      // app/providers.dart.
      ref.read(dataRefreshSignalProvider.notifier).state++;
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Income recorded.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFulusSnackbar(context, message: "Couldn't record this income. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    return FulusScreen(
      title: 'Add income',
      subtitle: 'Record money received outside a sale',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final inset = wide ? AppSpacing.lg : AppSpacing.sm;
          return ListView(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FulusCard(
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.selectedTintOf(context),
                              ),
                              child: Icon(Icons.south_west_rounded, color: AppColors.primaryOf(context)),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Other income',
                                    style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Add a clear source so the entry is easy to audit later.',
                                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FulusCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FulusTextField(
                              label: 'Amount',
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              hintText: '0.00',
                              errorText: _amountError,
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.lg),
                                child: Align(widthFactor: 1, child: Text(currencySymbol)),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FulusTextField(
                              label: 'Source',
                              controller: _sourceController,
                              hintText: 'e.g. Old shelf sold, space rental',
                              errorText: _sourceError,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FulusTextField(
                              label: 'Note (optional)',
                              controller: _noteController,
                              maxLines: 3,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            FulusButton(
                              label: 'Save income',
                              loading: _submitting,
                              onPressed: _submitting ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
