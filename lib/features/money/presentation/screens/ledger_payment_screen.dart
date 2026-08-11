import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../utils/money_format.dart';

const _kLedgerPaymentMethods = ['Cash', 'Mobile Money', 'Bank/Card'];

/// Volume 8, Decision 26: "Pay Supplier mirrors Record Repayment
/// exactly." One screen, used for both — [title]/[counterpartyLabel]/
/// [onSubmit] are the only things that differ between "a customer
/// paying down what they owe" and "the business paying down what it
/// owes a supplier"; the amount/method/note fields and the excess-
/// amount handling are identical either way.
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

  /// "Owed by" or "Owed to" — precedes [counterpartyName].
  final String counterpartyLabel;
  final String counterpartyName;
  final double outstandingBalance;
  final String currencySymbol;
  final String successMessage;

  /// Returns the ledger's new balance and, per Volume 7's own named
  /// failure scenario, how much of [amount] exceeded what was actually
  /// owed (0 when it didn't).
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
      _amountError = amount == null || amount <= 0 ? "Amount can't be ₦0" : null;
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
      body: ListView(
        children: [
          FulusCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.counterpartyName,
                      style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600),
                    ),
                    Text(
                      widget.counterpartyLabel,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
                Text(
                  formatMoney(widget.outstandingBalance, symbol: widget.currencySymbol),
                  style: AppTypography.heading.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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
          Text('Paid with', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
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
          SizedBox(
            width: double.infinity,
            child: FulusButton(label: 'Save', loading: _submitting, onPressed: _submitting ? null : _submit),
          ),
        ],
      ),
    );
  }
}
