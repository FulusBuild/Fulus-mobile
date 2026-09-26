import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';
import '../../core/ux/consumer_polish.dart';
import 'fulus_button.dart';

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
    this.padding = _defaultPadding,
    this.applyPadding = true,
    this.backgroundColor,
    this.headerBackgroundColor,
  });

  static const _defaultPadding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.lg,
    AppSpacing.xxl,
  );

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsets padding;
  final bool applyPadding;
  final Color? backgroundColor;
  final Color? headerBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null;
    final canPop = Navigator.of(context).canPop();
    final adaptivePadding = padding == _defaultPadding
        ? EdgeInsets.fromLTRB(
            FulusLayout.horizontalInset(context),
            padding.top,
            FulusLayout.horizontalInset(context),
            padding.bottom,
          )
        : padding;
    final content = applyPadding ? Padding(padding: adaptivePadding, child: body) : body;

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.backgroundOf(context),
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
                backgroundColor: headerBackgroundColor,
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: FulusLayout.maxContentWidth),
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

class _HeaderText extends StatelessWidget {
  const _HeaderText({
    required this.title,
    required this.subtitle,
    required this.isWide,
    required this.foreground,
    required this.muted,
  });

  final String title;
  final String? subtitle;
  final bool isWide;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: muted),
          ),
        ],
      ],
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
    this.backgroundColor,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final darkHeader = backgroundColor != null && backgroundColor!.computeLuminance() < 0.25;
    final muted = darkHeader ? Colors.white70 : AppColors.mutedOf(context);
    final foreground = darkHeader ? Colors.white : AppColors.textPrimaryOf(context);
    final width = FulusLayout.width(context);
    final isWide = width >= FulusLayout.wideBreakpoint;
    final inset = FulusLayout.horizontalInset(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final stackActions = actions != null &&
        actions!.isNotEmpty &&
        (width < 360 || textScale > 1.15);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.backgroundOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.65))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: FulusLayout.maxContentWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              inset,
              width >= FulusLayout.tabletBreakpoint ? AppSpacing.md : AppSpacing.xs,
              inset,
              width >= FulusLayout.tabletBreakpoint ? AppSpacing.md : AppSpacing.xs,
            ),
            child: stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (leading != null || showBack)
                            SizedBox(
                              width: AppTouchTarget.minimum,
                              height: AppTouchTarget.minimum,
                              child: leading ??
                                  FulusIconButton(
                                    icon: FulusIcons.arrowBack,
                                    tooltip: 'Go back',
                                    onPressed: () => Navigator.of(context).maybePop(),
                                  ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: leading != null || showBack ? AppSpacing.xs : 0,
                              ),
                              child: _HeaderText(
                                title: title,
                                subtitle: subtitle,
                                isWide: isWide,
                                foreground: foreground,
                                muted: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: actions!,
                        ),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                if (leading != null || showBack)
                  SizedBox(
                    width: AppTouchTarget.minimum,
                    height: AppTouchTarget.minimum,
                    child: leading ??
                        FulusIconButton(
                          icon: FulusIcons.arrowBack,
                          tooltip: 'Go back',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: leading != null || showBack ? AppSpacing.xs : 0),
                    child: _HeaderText(
                      title: title,
                      subtitle: subtitle,
                      isWide: isWide,
                      foreground: foreground,
                      muted: muted,
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
