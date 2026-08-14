import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Gap fix: Volume 5's discount action — "sits near the total... a flat
/// amount or a percentage, switchable... applying either to the whole
/// sale or one line" — had no UI anywhere. `DraftCartRepository.
/// updateItemDiscount`/`setWholeCartDiscount` already existed with no
/// caller; this sheet is that missing caller, shared between the
/// whole-cart and per-line cases (identical UI, different [baseAmount]
/// and [onSave] target) rather than building two near-duplicate sheets.
class DiscountSheet extends StatefulWidget {
  const DiscountSheet({
    super.key,
    required this.title,
    required this.baseAmount,
    required this.currencySymbol,
    required this.initialDiscount,
    required this.onSave,
  });

  final String title;

  /// Subtotal (whole-cart case) or this one line's total (per-line
  /// case) — the ceiling a flat-amount discount can't exceed, and what
  /// a percentage is calculated against.
  final double baseAmount;
  final String currencySymbol;
  final double initialDiscount;
  final Future<void> Function(double discountAmount) onSave;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required double baseAmount,
    required String currencySymbol,
    required double initialDiscount,
    required Future<void> Function(double discountAmount) onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DiscountSheet(
        title: title,
        baseAmount: baseAmount,
        currencySymbol: currencySymbol,
        initialDiscount: initialDiscount,
        onSave: onSave,
      ),
    );
  }

  @override
  State<DiscountSheet> createState() => _DiscountSheetState();
}

enum _DiscountMode { amount, percent }

class _DiscountSheetState extends State<DiscountSheet> {
  late _DiscountMode _mode;
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = _DiscountMode.amount;
    final initial = widget.initialDiscount > 0 ? widget.initialDiscount.toStringAsFixed(2) : '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _enteredValue => double.tryParse(_controller.text.trim());

  /// Resolves whatever's typed, in whichever mode is active, down to a
  /// flat currency amount — the only shape `updateItemDiscount`/
  /// `setWholeCartDiscount` actually accept.
  double? get _resolvedDiscountAmount {
    final value = _enteredValue;
    if (value == null) return null;
    if (_mode == _DiscountMode.percent) {
      return widget.baseAmount * (value / 100);
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedDiscountAmount;
    final resultingTotal = widget.baseAmount - (resolved ?? 0).clamp(0, widget.baseAmount);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<_DiscountMode>(
            segments: const [
              ButtonSegment(value: _DiscountMode.amount, label: Text('Amount')),
              ButtonSegment(value: _DiscountMode.percent, label: Text('Percent')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          FulusTextField(
            label: _mode == _DiscountMode.amount ? 'Discount amount' : 'Discount percent',
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: _error,
            onChanged: (_) => setState(() {}),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Align(
                widthFactor: 1,
                child: Text(_mode == _DiscountMode.amount ? widget.currencySymbol : '%'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('New total', style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
              Text(
                '${widget.currencySymbol}${resultingTotal.toStringAsFixed(2)}',
                style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (widget.initialDiscount > 0)
                Expanded(
                  child: FulusButton(
                    label: 'Remove discount',
                    variant: FulusButtonVariant.secondary,
                    loading: _saving,
                    onPressed: _saving ? null : () => _save(0),
                  ),
                ),
              if (widget.initialDiscount > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FulusButton(
                  label: 'Apply',
                  loading: _saving,
                  onPressed: _saving ? null : () => _save(resolved),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save(double? amount) async {
    if (amount == null) {
      setState(() => _error = 'Enter a number.');
      return;
    }
    if (amount < 0) {
      setState(() => _error = "Discount can't be negative.");
      return;
    }
    if (amount > widget.baseAmount) {
      setState(() => _error = "Discount can't be more than ${widget.currencySymbol}${widget.baseAmount.toStringAsFixed(2)}.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(amount);
      if (mounted) Navigator.of(context).pop();
    } on StateError catch (e) {
      if (mounted) setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }
}
