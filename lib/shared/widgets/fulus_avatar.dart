import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A round initials avatar — Redesign pass addition. Nothing in the
/// shared widget set covered "represent a person or business with no
/// photo" before this; Home's new greeting header and Team's roster
/// rows both need exactly this, so it lives here rather than being
/// hand-rolled twice. Deliberately initials-only, no photo slot — no
/// avatar-photo concept exists anywhere in the domain layer yet (owner
/// accounts and employees have names, not profile pictures), so this
/// doesn't invent a fallback path for an image source that can't
/// currently be populated.
class FulusAvatar extends StatelessWidget {
  const FulusAvatar({super.key, required this.name, this.size = 40, this.backgroundColor, this.foregroundColor});

  final String name;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.selectedTintOf(context);
    final fg = foregroundColor ?? AppColors.primaryOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: AppTypography.label.copyWith(
          color: fg,
          fontSize: size * 0.4,
          letterSpacing: 0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
