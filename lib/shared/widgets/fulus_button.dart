import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

enum FulusButtonVariant { primary, secondary, destructive, text }

/// Shared action primitive. Blue is the only interaction colour; white and
/// black provide the neutral foundation. Buttons keep a strong primary
/// hierarchy, clear pressed feedback, and 48dp minimum touch targets.
class FulusButton extends StatelessWidget {
  const FulusButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = FulusButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final FulusButtonVariant variant;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final child = _buildChild(context);
    final minimumSize = const Size(48, 48);

    switch (variant) {
      case FulusButtonVariant.primary:
        return ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryOf(context),
            foregroundColor: AppColors.onPrimaryOf(context),
            disabledBackgroundColor: AppColors.primaryOf(context).withValues(alpha: AppOpacity.disabled),
            disabledForegroundColor: AppColors.onPrimaryOf(context).withValues(alpha: AppOpacity.disabled),
            minimumSize: minimumSize,
            elevation: 0,
          ),
          child: child,
        );
      case FulusButtonVariant.secondary:
        return OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimaryOf(context),
            side: BorderSide(color: AppColors.borderOf(context)),
            minimumSize: minimumSize,
          ),
          child: child,
        );
      case FulusButtonVariant.destructive:
        return ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.errorOf(context),
            foregroundColor: AppColors.errorOnOf(context),
            disabledBackgroundColor: AppColors.errorOf(context).withValues(alpha: AppOpacity.disabled),
            disabledForegroundColor: AppColors.errorOnOf(context).withValues(alpha: AppOpacity.disabled),
            minimumSize: minimumSize,
            elevation: 0,
          ),
          child: child,
        );
      case FulusButtonVariant.text:
        return TextButton(
          onPressed: disabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryOf(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: minimumSize,
          ),
          child: child,
        );
    }
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppIconSize.compact,
            height: AppIconSize.compact,
            child: CircularProgressIndicator(
              strokeWidth: AppIconSize.strokeWidth,
              valueColor: AlwaysStoppedAnimation(_foregroundColor(context)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(loadingLabel ?? 'Loading'),
        ],
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.compact),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }

  Color _foregroundColor(BuildContext context) {
    switch (variant) {
      case FulusButtonVariant.primary:
        return AppColors.onPrimaryOf(context);
      case FulusButtonVariant.destructive:
        return AppColors.errorOnOf(context);
      case FulusButtonVariant.secondary:
      case FulusButtonVariant.text:
        return AppColors.primaryOf(context);
    }
  }
}

/// Icon actions retain the full 48dp hit area while keeping the glyph quiet.
class FulusIconButton extends StatelessWidget {
  const FulusIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryOf(context),
              foregroundColor: AppColors.onPrimaryOf(context),
              minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
            ),
          )
        : IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimaryOf(context),
              minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
            ),
          );
    final wrapped = tooltip == null ? button : Tooltip(message: tooltip!, child: button);
    return tooltip == null
        ? wrapped
        : Semantics(button: true, label: tooltip, excludeSemantics: true, child: wrapped);
  }
}
