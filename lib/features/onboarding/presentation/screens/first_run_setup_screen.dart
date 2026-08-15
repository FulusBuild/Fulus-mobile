import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Nice-to-have gap closure — Volume 3's "Printer Setup — Optional, Not
/// a Blocker" and "First Product & First Customer — Both Optional, Both
/// Minimal" sections, folded into one screen rather than three separate
/// ones. The Bible describes these as reachable steps between business
/// creation and First Sale, each individually skippable; this screen is
/// that bridge, shown exactly once per business (see
/// [OnboardingState.hasSeenFirstRunPrompt]'s doc comment for the
/// default-true/armed-at-creation reasoning), inserted by router.dart's
/// `_ShellGate` between [OwnerSetupScreen] finishing and the app shell
/// actually rendering.
///
/// Deliberately doesn't build three separate screens for
/// printer/product/customer the way the Bible's prose lists them —
/// First Customer specifically only matters "if a sale is made on
/// credit," which the existing Add-Customer flow already handles
/// on-demand from Sell/Stock, so a dedicated onboarding screen for it
/// here would just be a detour to a form this owner may never need on
/// day one. What's kept is the substance PROGRESS.md's own nice-to-have
/// line names directly: a first-product prompt, a quick-sale prompt,
/// and (since Volume 3 groups it with these same optional steps, and
/// the screen it points to already exists in full) a printer-pairing
/// link.
///
/// Tapping ANY option here — including "Skip for now" — marks the
/// prompt seen and is never shown again, matching Volume 3's "Neither
/// screen blocks progress to First Sale" read as "shown once, not
/// shown until completed."
class FirstRunSetupScreen extends ConsumerWidget {
  const FirstRunSetupScreen({super.key});

  Future<void> _dismiss(WidgetRef ref) async {
    await ref.read(onboardingStateProvider).markFirstRunPromptSeen();
    ref.read(firstRunPromptSeenProvider.notifier).state = true;
  }

  /// Shared by every option below: mark this one-time screen seen
  /// first, then navigate — go_router re-resolves the whole
  /// `StatefulShellRoute` against the new location, and by the time
  /// `_ShellGate` rebuilds, [firstRunPromptSeenProvider] already reads
  /// true, so it renders `FulusAppShell` (already showing the target
  /// branch/screen go_router resolved) instead of this screen again.
  Future<void> _go(BuildContext context, WidgetRef ref, String routeName) async {
    await _dismiss(ref);
    if (context.mounted) context.goNamed(routeName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "You're all set.",
              style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A few optional things to help you get going — skip any of '
              'this any time, none of it is required before your first sale.',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _OptionCard(
              icon: Icons.inventory_2_outlined,
              title: 'Add your first product',
              subtitle: 'Name and price — everything else can wait.',
              onTap: () => _go(context, ref, 'stockAddProduct'),
            ),
            const SizedBox(height: AppSpacing.md),
            _OptionCard(
              icon: Icons.point_of_sale_outlined,
              title: 'Sell something now',
              subtitle: "No product needed yet — Quick Sale rings up a custom amount.",
              onTap: () => _go(context, ref, 'sell'),
            ),
            const SizedBox(height: AppSpacing.md),
            _OptionCard(
              icon: Icons.print_outlined,
              title: 'Pair a printer',
              subtitle: 'Optional — receipts work fine without one, too.',
              onTap: () => _go(context, ref, 'moreSettingsPrinters'),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: "Skip for now",
                variant: FulusButtonVariant.text,
                onPressed: () => _dismiss(ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              // 0.1 tint on the primary color — matching the icon-badge
              // treatment SaleSuccessScreen's own checkmark circle
              // already uses, rather than inventing a new value.
              color: AppColors.primaryOf(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
        ],
      ),
    );
  }
}
