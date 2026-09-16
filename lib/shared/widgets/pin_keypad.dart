import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A compact, touch-friendly numeric keypad for secure PIN entry.
///
/// The keypad is deliberately visual rather than a platform text field so
/// the lock screen feels like a purpose-built secure surface on phones and
/// tablets. The caller owns the PIN state and verification lifecycle.
class FulusPinKeypad extends StatelessWidget {
  const FulusPinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final keySize = ((width - AppSpacing.lg * 2) / 3).clamp(64.0, 92.0);
        return SizedBox(
          width: keySize * 3 + AppSpacing.lg * 2,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: keys.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: keySize,
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemBuilder: (context, index) {
              final key = keys[index];
              if (key.isEmpty) return const SizedBox.shrink();
              final isBackspace = key == 'back';
              return _PinKey(
                label: isBackspace ? null : key,
                icon: isBackspace ? Icons.backspace_outlined : null,
                enabled: enabled,
                onTap: isBackspace ? onBackspace : () => onDigit(key),
              );
            },
          ),
        );
      },
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final text = AppColors.textPrimaryOf(context);
    final border = AppColors.borderOf(context);
    return Semantics(
      button: true,
      label: label == null ? 'Delete last digit' : 'Digit $label',
      child: Material(
        color: AppColors.surfaceOf(context),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: border.withValues(alpha: .72)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .035),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: TextStyle(
                        fontSize: 24,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: enabled ? text : AppColors.textSecondaryOf(context),
                      ),
                    )
                  : Icon(
                      icon,
                      size: 21,
                      color: enabled ? text : AppColors.textSecondaryOf(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
