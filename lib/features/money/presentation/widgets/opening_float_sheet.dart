import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';

/// Volume 8's Cash Drawer & Opening Float — asked once, at the start of
/// a day, "one more thing than a bare 'ready to open'" per the Bible's
/// own framing for what Home's Open Shop action should trigger.
/// Returns `true` if a drawer was opened.
Future<bool> showOpeningFloatSheet(BuildContext context) async {
  final result = await showFulusBottomSheet<bool>(
    context: context,
    title: 'Opening float',
    builder: (sheetContext) => const _OpeningFloatForm(),
  );
  return result ?? false;
}

class _OpeningFloatForm extends ConsumerStatefulWidget {
  const _OpeningFloatForm();

  @override
  ConsumerState<_OpeningFloatForm> createState() => _OpeningFloatFormState();
}

class _OpeningFloatFormState extends ConsumerState<_OpeningFloatForm> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_controller.text.replaceAll(',', '').trim());
    if (amount == null || amount < 0) {
      setState(() => _error = 'Enter how much cash is in the drawer.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(moneyRepositoryProvider).openDrawer(openingFloat: amount);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFulusSnackbar(context, message: "Couldn't open the drawer. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How much cash is in the drawer to start the day?',
          style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: AppSpacing.md),
        FulusTextField(
          label: 'Opening float',
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hintText: '0.00',
          errorText: _error,
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Align(
              widthFactor: 1,
              child: Text(ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦'),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FulusButton(label: 'Confirm', loading: _submitting, onPressed: _submitting ? null : _confirm),
        ),
      ],
    );
  }
}
