import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Shared page composition for secondary and detail screens.
///
/// The layout is intentionally editorial rather than dashboard-like:
/// navigation sits above a strong serif title, supporting context is quiet,
/// actions live at the edge of the header, and a single hairline separates
/// navigation from content. This gives every feature screen a recognizable
/// Fulus rhythm without forcing feature code to duplicate chrome.
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
    final content = applyPadding
        ? Padding(padding: padding, child: body)
        : body;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: Column(
          children: [
            if (hasHeader)
              _EditorialPageHeader(
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
                  constraints: const BoxConstraints(maxWidth: 960),
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

class _EditorialPageHeader extends StatelessWidget {
  const _EditorialPageHeader({
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
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
              padding: EdgeInsets.only(left: leading != null || showBack ? AppSpacing.xs : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.heading.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.mutedOf(context),
                      ),
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
    );
  }
}
