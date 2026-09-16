import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';

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
    final action = disabled
        ? null
        : () {
            FulusHaptics.selection();
            onPressed!();
          };
    final child = _buildChild(context);
    const minimumSize = Size(48, 48);

    switch (variant) {
      case FulusButtonVariant.primary:
        return ElevatedButton(
          onPressed: action,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryOf(context),
            foregroundColor: AppColors.onPrimaryOf(context),
            disabledBackgroundColor: AppColors.primaryOf(context).withValues(alpha: AppOpacity.disabled),
            disabledForegroundColor: AppColors.onPrimaryOf(context).withValues(alpha: AppOpacity.disabled),
            minimumSize: minimumSize,
            elevation: 0,
            textStyle: AppTypography.buttonLabel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: child,
        );
      case FulusButtonVariant.secondary:
        return OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimaryOf(context),
            side: BorderSide(color: AppColors.borderOf(context)),
            minimumSize: minimumSize,
            textStyle: AppTypography.buttonLabel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: child,
        );
      case FulusButtonVariant.destructive:
        return ElevatedButton(
          onPressed: action,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.errorOf(context),
            foregroundColor: AppColors.errorOnOf(context),
            disabledBackgroundColor: AppColors.errorOf(context).withValues(alpha: AppOpacity.disabled),
            disabledForegroundColor: AppColors.errorOnOf(context).withValues(alpha: AppOpacity.disabled),
            minimumSize: minimumSize,
            elevation: 0,
            textStyle: AppTypography.buttonLabel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: child,
        );
      case FulusButtonVariant.text:
        return TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryOf(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: minimumSize,
            textStyle: AppTypography.buttonLabel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: child,
        );
    }
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          SizedBox(
            width: AppIconSize.compact,
            height: AppIconSize.compact,
            child: CircularProgressIndicator(
              strokeWidth: AppIconSize.strokeWidth,
              valueColor: AlwaysStoppedAnimation(_foregroundColor(context)),
            ),
          ),
          Text(loadingLabel ?? 'Loading'),
        ],
      );
    }
    if (icon == null) return Text(label, textAlign: TextAlign.center);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        Icon(icon, size: AppIconSize.compact),
        Text(label, textAlign: TextAlign.center),
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
    final action = onPressed == null
        ? null
        : () {
            FulusHaptics.selection();
            onPressed!();
          };
    final foreground = filled ? AppColors.onPrimaryOf(context) : AppColors.textPrimaryOf(context);
    final button = IconButton(
      onPressed: action,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: filled ? AppColors.primaryOf(context) : Colors.transparent,
        foregroundColor: foreground,
        minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
        maximumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        overlayColor: AppColors.primaryOf(context).withValues(alpha: 0.10),
      ),
    );
    final wrapped = tooltip == null ? button : Tooltip(message: tooltip!, child: button);
    return tooltip == null
        ? wrapped
        : Semantics(button: true, label: tooltip, excludeSemantics: true, child: wrapped);
  }
}
