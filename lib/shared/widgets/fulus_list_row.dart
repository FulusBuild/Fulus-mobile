import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// The default way to show more than 3–4 of anything — Component
/// Library 5.4. Row height floors at 48dp but grows with content
/// ("never clipped to force a fixed height"); [leading] is the optional
/// 40dp icon/thumbnail tile "used whenever the row represents something
/// visual... rather than a pure setting toggle."
///
/// Pair with [FulusListDivider] in a `ListView.separated` — the divider
/// is its own widget rather than built into this row, since the Bible's
/// rule ("full-bleed under the content column only — not under the
/// leading icon") needs to know this row's leading-element width to
/// indent correctly, and a separator widget can't see its neighbors.
class FulusListRow extends StatelessWidget {
  const FulusListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;

  /// Sized to 40dp by this widget — pass an icon or a thumbnail image,
  /// not a pre-sized box.
  final Widget? leading;

  /// Right-aligned. Pass tabular-figure [Text] for numeric values, per
  /// 5.4's "Trailing value" rule.
  final Widget? trailing;
  final VoidCallback? onTap;

  static const leadingSize = 40.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        splashColor: AppColors.primaryOf(context).withValues(alpha: 0.10),
        highlightColor: AppColors.primaryOf(context).withValues(alpha: 0.06),
        hoverColor: AppColors.primaryOf(context).withValues(alpha: 0.04),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox(width: leadingSize, height: leadingSize, child: leading),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
                        child: title,
                      ),
                      if (subtitle != null)
                        DefaultTextStyle.merge(
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                          child: subtitle!,
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1px divider matching [FulusListRow]'s leading-element indent, so a
/// row with a leading icon and one without both line up under the same
/// "full-bleed under the content column only" rule (5.4).
class FulusListDivider extends StatelessWidget {
  const FulusListDivider({super.key, this.indented = true});

  /// False for a row with no [FulusListRow.leading] — a full-width divider.
  final bool indented;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: indented ? AppSpacing.lg + FulusListRow.leadingSize + AppSpacing.md : 0,
      ),
      child: Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
    );
  }
}
