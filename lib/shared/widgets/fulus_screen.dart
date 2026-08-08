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
    this.actions,
    this.floatingActionButton,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.applyPadding = true,
  });

  /// Page title shown in the app bar. If null, no [AppBar] is built —
  /// use this for screens that render their own custom header (e.g. a
  /// hero card standing in for a title, as Home's does).
  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;

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
      appBar: title == null ? null : AppBar(title: Text(title!), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: applyPadding ? Padding(padding: padding, child: body) : body,
      ),
    );
  }
}
