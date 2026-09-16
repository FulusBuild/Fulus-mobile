import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Shared page composition for secondary and detail screens.
///
/// The shell keeps navigation quiet and lets the current task own the screen.
/// A single responsive header is used throughout the workspace so feature
/// screens feel like one product rather than separate admin pages.
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
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
    this.applyPadding = true,
  });

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsets padding;
  final bool applyPadding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null;
    final canPop = Navigator.of(context).canPop();
    final content = applyPadding ? Padding(padding: padding, child: body) : body;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: Column(
          children: [
            if (hasHeader)
              _PageHeader(
                title: title!,
                subtitle: subtitle,
                actions: actions,
                leading: leading,
                showBack: canPop && leading == null,
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.leading,
    required this.showBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedOf(context);
    final foreground = AppColors.textPrimaryOf(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.55))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null || showBack)
              SizedBox(
                width: AppTouchTarget.minimum,
                height: AppTouchTarget.minimum,
                child: leading ?? const BackButton(),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: leading != null || showBack ? AppSpacing.xs : AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w750,
                        color: foreground,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (actions != null)
              ...actions!.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: action,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
