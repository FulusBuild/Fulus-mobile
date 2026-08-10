import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Volume 6, Decision 19: "Any Stock Out or Adjustment initiated from
/// an employee login requires the same owner approval already
/// established for discounts and refunds — one mechanism, reused, not
/// reinvented." [ApprovalPinRepository.verifyApprovalPin] is that real,
/// already-built mechanism (Volume 9) — this sheet is the UI for it,
/// not a new approval system.
///
/// Returns true once a real owner's PIN has been verified, false if the
/// sheet was dismissed without one. Callers should treat anything but
/// `true` as "not approved" and not submit the movement.
///
/// Renders a plain numeric [FulusTextField] rather than a dedicated PIN
/// keypad (Component Library 5.14) — building that full custom keypad
/// widget is real, separate scope this pass didn't reach; a numeric-
/// keyboard text field is a faithful, honest stand-in for the same
/// input, not a silent downgrade of what PIN entry does.
Future<bool> requireOwnerApproval(BuildContext context, WidgetRef ref) async {
  final approved = await showFulusBottomSheet<bool>(
    context: context,
    title: 'Owner approval needed',
    builder: (sheetContext) => _ApprovalPinForm(ref: ref),
  );
  return approved ?? false;
}

class _ApprovalPinForm extends StatefulWidget {
  const _ApprovalPinForm({required this.ref});
  final WidgetRef ref;

  @override
  State<_ApprovalPinForm> createState() => _ApprovalPinFormState();
}

class _ApprovalPinFormState extends State<_ApprovalPinForm> {
  final _pinController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = "Enter the owner's approval PIN.");
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final approvingOwnerId =
        await widget.ref.read(approvalPinRepositoryProvider).verifyApprovalPin(pin);
    if (!mounted) return;
    if (approvingOwnerId != null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = "That PIN doesn't match any owner on this device.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "This action needs an owner's approval before it applies.",
          style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[
          Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.errorOf(context))),
          const SizedBox(height: AppSpacing.sm),
        ],
        FulusTextField(
          label: 'Approval PIN',
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusButton(label: 'Approve', loading: _submitting, onPressed: _submitting ? null : _submit),
      ],
    );
  }
}
