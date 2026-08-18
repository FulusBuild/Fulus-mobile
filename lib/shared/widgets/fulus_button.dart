import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Button variant — Volume 5.1's five kinds, minus the two Icon
/// variants (their own widget, [FulusIconButton], since their layout
/// is a circle rather than a label pill).
enum FulusButtonVariant { primary, secondary, destructive, text }

/// The button kinds from Component Library 5.1, collapsed into one
/// widget parameterized by [variant] rather than one widget per kind —
/// per the foundation brief's rule against feature-specific
/// reimplementations. Height floors at [AppTouchTarget.minimum] (48dp,
/// "never smaller, even for a compact button" per the Bible) via the
/// button themes already set in [AppTheme] — this widget doesn't repeat
/// that sizing itself, it relies on it, so a future change to the
/// height floor happens in exactly one place.
///
/// Wrap in `SizedBox(width: double.infinity, ...)` at the call site for
/// a full-width button — this widget doesn't force a width itself,
/// matching how buttons are already used in Home's own hero button.
///
/// Two rules this widget can't enforce on its own, but the Bible
/// states: "One Primary per screen," and "Destructive always confirms"
/// — see `fulus_dialogs.dart`'s `showFulusConfirmDialog` for the
/// confirm step a Destructive button's `onPressed` should await before
/// its actual destructive logic runs.
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

  /// Present-tense label shown while [loading] is true — "Processing",
  /// never the original label struck through (5.1, Loading row).
  /// Defaults to "Loading" if not given.
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final FulusButtonVariant variant;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final child = _buildChild(context);

    switch (variant) {
      case FulusButtonVariant.primary:
        return ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryOf(context),
            foregroundColor: AppColors.onPrimaryOf(context),
            disabledBackgroundColor: AppColors.primaryOf(context).withOpacity(AppOpacity.disabled),
            disabledForegroundColor: AppColors.onPrimaryOf(context).withOpacity(AppOpacity.disabled),
          ),
          child: child,
        );
      case FulusButtonVariant.secondary:
        return OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryOf(context),
            side: BorderSide(color: AppColors.primaryOf(context)),
          ),
          child: child,
        );
      case FulusButtonVariant.destructive:
        return ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.errorOf(context),
            foregroundColor: AppColors.errorOnOf(context),
            disabledBackgroundColor: AppColors.errorOf(context).withOpacity(AppOpacity.disabled),
            disabledForegroundColor: AppColors.errorOnOf(context).withOpacity(AppOpacity.disabled),
          ),
          child: child,
        );
      case FulusButtonVariant.text:
        return TextButton(
          onPressed: disabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryOf(context),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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

/// Icon button — Bible 5.1's "Icon (outlined)" and "Icon (filled)"
/// variants. Always a real 48×48dp tap target even though the glyph
/// itself renders smaller — the extra padding is real space, not a
/// visual illusion, so screen readers and fat-finger taps both get the
/// full target (Accessibility, Touch target row).
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
