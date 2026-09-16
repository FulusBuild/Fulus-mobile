import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../utils/money_format.dart';

const _kLedgerPaymentMethods = ['Cash', 'Mobile Money', 'Bank/Card'];

/// Shared payment workspace for customer repayments and supplier payments.
/// Business behaviour stays in the injected repository callback; this
/// screen owns only validation, presentation and feedback.
class LedgerPaymentScreen extends StatefulWidget {
  const LedgerPaymentScreen({
    super.key,
    required this.title,
    required this.counterpartyLabel,
    required this.counterpartyName,
    required this.outstandingBalance,
    required this.currencySymbol,
    required this.onSubmit,
    required this.successMessage,
  });

  final String title;
  final String counterpartyLabel;
  final String counterpartyName;
  final double outstandingBalance;
  final String currencySymbol;
  final String successMessage;

  final Future<({double newBalance, double excessAmount})> Function({
    required double amount,
    required String paymentMethod,
    String? note,
  }) onSubmit;

  @override
  State<LedgerPaymentScreen> createState() => _LedgerPaymentScreenState();
}

class _LedgerPaymentScreenState extends State<LedgerPaymentScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _paymentMethod;
  String? _amountError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.outstandingBalance > 0) {
      _amountController.text = widget.outstandingBalance.toStringAsFixed(0);
    }
  }

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
      _amountError = amount == null || amount <= 0 ? "Amount can't be ${widget.currencySymbol}0" : null;
    });
    if (_amountError != null) return;
    if (_paymentMethod == null) {
      showFulusSnackbar(context, message: 'Choose how it was paid.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await widget.onSubmit(
        amount: amount!,
        paymentMethod: _paymentMethod!,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (mounted) {
        ProviderScope.containerOf(context, listen: false).read(dataRefreshSignalProvider.notifier).state++;
      }
      if (!mounted) return;
      if (result.excessAmount > 0) {
        showFulusSnackbar(
          context,
          message:
              'That was ${formatMoney(result.excessAmount, symbol: widget.currencySymbol)} more than was owed — recorded, balance is now zero.',
        );
      } else {
        showFulusSnackbar(context, message: widget.successMessage);
      }
      context.pop(true);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _amountError = e.message?.toString() ?? "That amount isn't valid.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFulusSnackbar(context, message: "Couldn't record this. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: widget.title,
      subtitle: '${widget.counterpartyLabel} ${widget.counterpartyName}',
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.selectedTintOf(context),
                                  ),
                                  child: Icon(Icons.payments_outlined, color: AppColors.primaryOf(context)),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.counterpartyName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                                      ),
                                      Text(
                                        widget.counterpartyLabel,
                                        style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'Outstanding balance',
                              style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatMoney(widget.outstandingBalance, symbol: widget.currencySymbol),
                                style: AppTypography.display.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
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
                                child: Align(widthFactor: 1, child: Text(widget.currencySymbol)),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text('Paid with', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                            const SizedBox(height: AppSpacing.sm),
                            FulusChipRow(
                              children: [
                                for (final method in _kLedgerPaymentMethods)
                                  FulusChip(
                                    label: method,
                                    selected: _paymentMethod == method,
                                    onTap: () => setState(() => _paymentMethod = method),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FulusTextField(label: 'Note (optional)', controller: _noteController, maxLines: 3),
                            const SizedBox(height: AppSpacing.xl),
                            FulusButton(
                              label: 'Save payment',
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
