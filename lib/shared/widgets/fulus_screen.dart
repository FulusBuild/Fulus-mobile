import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// The standard page container every screen should build on — the
/// foundation brief's "Page/screen containers" item. Wraps [Scaffold] +
/// [SafeArea] + the app's standard screen padding, and resolves
/// background color for the active theme via [AppColors.backgroundOf]
/// so a screen doesn't need to hardcode `AppColors.backgroundLight` the
/// way Home and Employees do today (see design_tokens.dart's
/// brightness-accessor comment for why those two screens are a known,
/// out-of-scope-for-this-phase gap this widget doesn't repeat).
///
/// Set [applyPadding] to false for screens that build their own
/// [ListView]/[CustomScrollView] wanting edge-to-edge content (so this
/// doesn't double-pad); [FulusScreen] itself does not scroll — it just
/// supplies the Scaffold, SafeArea, and padding around whatever [body]
/// is.
class FulusScreen extends StatelessWidget {
  const FulusScreen({
    super.key,
    required this.body,
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.applyPadding = true,
  });

  /// Page title shown in the app bar. If null, no [AppBar] is built —
  /// use this for screens that render their own custom header (e.g. a
  /// hero card standing in for a title, as Home's does).
  final String? title;

  /// Redesign pass addition — a small secondary line under [title]
  /// (e.g. a count, a date range). Purely additive; every existing
  /// call site leaves this unset and renders exactly as before.
  final String? subtitle;
  final List<Widget>? actions;

  /// Redesign pass addition — overrides the default back button when
  /// set. Unset (the common case) preserves Flutter's own automatic
  /// back/close button.
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;

  /// Redesign pass addition — purely additive passthrough to
  /// [Scaffold.bottomNavigationBar].
  final Widget? bottomNavigationBar;

  /// Applied around [body] when [applyPadding] is true. Defaults to
  /// [AppSpacing.lg] on all sides, matching Home's existing screen
  /// padding.
  final EdgeInsets padding;

  /// Set false when [body] manages its own padding per-section (e.g. a
  /// list that wants edge-to-edge dividers with padding only on text).
  final bool applyPadding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: title == null
          ? null
          : AppBar(
              backgroundColor: AppColors.backgroundOf(context),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              // A hairline only appears once content actually scrolls
              // under the bar — "resting" elevation stays flat per
              // AppElevation's own two-level system; this is Material
              // 3's own scroll-aware affordance, not a third bespoke
              // elevation tier.
              scrolledUnderElevation: 0.5,
              shadowColor: AppColors.borderOf(context),
              leading: leading,
              titleSpacing: leading == null ? null : 0,
              title: subtitle == null
                  ? Text(title!, style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title!, style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
                        Text(subtitle!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                      ],
                    ),
              actions: actions,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: AppColors.borderOf(context)),
              ),
            ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: applyPadding ? Padding(padding: padding, child: body) : body,
      ),
    );
  }
}
