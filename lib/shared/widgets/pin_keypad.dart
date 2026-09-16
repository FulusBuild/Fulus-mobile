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
        final keySize = ((width - AppSpacing.lg * 2) / 3).clamp(68.0, 92.0);
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
                icon: isBackspace ? Icons.backspace_rounded : null,
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
    final text = AppColors.textPrimaryOf(context);
    final secondary = AppColors.textSecondaryOf(context);
    final border = AppColors.borderOf(context);
    final surface = AppColors.surfaceOf(context);
    final isBackspace = label == null;

    return Semantics(
      button: true,
      label: isBackspace ? 'Delete last digit' : 'Digit $label',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isBackspace ? surface.withValues(alpha: .72) : surface,
              border: Border.all(color: border.withValues(alpha: .55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .055),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: TextStyle(
                        fontSize: 23,
                        height: 1,
                        fontWeight: FontWeight.w650,
                        color: enabled ? text : secondary,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 20,
                      color: enabled ? text : secondary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
