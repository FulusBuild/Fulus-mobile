import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';
import 'fulus_button.dart';
import 'fulus_brand_logo.dart';

/// Shared page composition for secondary and detail screens.
/// Keeps the workspace visually consistent across phone and tablet widths.
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
    this.showMenu = true,
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
  final bool showMenu;

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
                showMenu: showMenu && !canPop && leading == null,
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
    required this.showMenu,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedOf(context);
    final foreground = AppColors.textPrimaryOf(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.55))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? AppSpacing.lg : AppSpacing.lg,
              isWide ? AppSpacing.md : AppSpacing.xs,
              isWide ? AppSpacing.lg : AppSpacing.lg,
              isWide ? AppSpacing.md : AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null || showBack || showMenu)
                  SizedBox(
                    width: AppTouchTarget.minimum,
                    height: AppTouchTarget.minimum,
                    child: leading ?? (showBack
                        ? FulusIconButton(
                            icon: FulusIcons.arrowBack,
                            tooltip: 'Go back',
                            onPressed: () => Navigator.of(context).maybePop(),
                          )
                        : FulusIconButton(
                            icon: FulusIcons.menu,
                            tooltip: 'Open navigation',
                            onPressed: FulusAppShell.openDrawer,
                          )),
                  ),
                if (showMenu) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const FulusBrandLogo(size: 40, padding: 7),
                  const SizedBox(width: AppSpacing.md),
                ],
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
                            fontSize: isWide ? 22 : 20,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                            letterSpacing: -0.35,
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
        ),
      ),
    );
  }
}
