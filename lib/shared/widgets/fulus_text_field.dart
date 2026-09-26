import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A labeled text input — Component Library 5.7. The label is always
/// visible above the field (never a placeholder-only label) via
/// [AppTheme]'s app-wide `floatingLabelBehavior: .always` — this widget
/// doesn't repeat that, only [label] and [errorText] need supplying at
/// the call site.
///
/// Field height isn't pinned to an exact 52dp here (Flutter's TextField
/// sizes from font size + content padding, not a height property) —
/// `contentPadding` below is tuned to land close to the Bible's 52dp
/// target, but wasn't verified pixel-for-pixel on a device (no Flutter
/// toolchain was available while writing this). Worth a quick visual
/// check against 5.7's spec the first time this renders on a real
/// screen.
class FulusTextField extends StatelessWidget {
  const FulusTextField({
    super.key,
    required this.label,
    this.controller,
    this.helperText,
    this.errorText,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
    this.onTap,
    this.suffixIcon,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController? controller;
  final String? helperText;

  /// "A specific helper message replaces generic placeholder text —
  /// 'Price can't be ₦0,' never just 'Invalid input.'" (5.7) — the
  /// caller supplies that specific copy here.
  final String? errorText;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      onChanged: onChanged,
      onTap: onTap,
      maxLines: obscureText ? 1 : maxLines,
      style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: errorText == null ? helperText : null,
        errorText: errorText,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
    );
  }
}
