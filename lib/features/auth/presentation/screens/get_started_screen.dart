import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import 'owner_setup_screen.dart';

/// Nice-to-have gap closure — Volume 3, "Install & Launch": "First
/// launch goes straight to a single, unambiguous 'Get started' action —
/// no login form, no blank splash screen waiting on a network call."
///
/// Before this screen existed, [AuthGateScreen] built [OwnerSetupScreen]
/// directly the moment it confirmed no owner account exists on the
/// device — a correct decision (no login form shown to someone who has
/// nothing to log into yet) but not what the Bible actually specifies
/// for the very first thing a new install shows: a two-field form
/// (business name, "Owner name / username / password") rather than one
/// unambiguous action to tap. This screen is that one action, standing
/// in front of [OwnerSetupScreen] rather than replacing it — everything
/// [OwnerSetupScreen] already does (account, then business, resumable
/// if interrupted) is untouched.
///
/// Purely static — no repository read, no `FutureBuilder`, nothing
/// awaited before the first frame — matching "Target: interactive in
/// under 3 seconds on a 2GB-RAM device" as directly as a single stateless
/// widget can.
///
/// The Employee half of Volume 3's Install & Launch ("Kwame's first
/// launch starts with 'I have a code' instead of 'Get started'") is
/// deliberately not built here — that path depends on the employee
/// cross-device invite/QR flow, which PROGRESS.md already tracks
/// separately as its own not-yet-started nice-to-have. Adding an "I have
/// a code" button with nothing on the other end of it would be worse
/// than not offering it at all, per Volume 12's "never a dead end"
/// production rule — see [AuthGateScreen]'s own doc comment for the
/// same reasoning applied to sign-in.
class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      body: Column(
        children: [
          const Spacer(flex: 3),
          _Mark(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Fulus',
            style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sales, stock, and money — run your shop from your pocket.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const Spacer(flex: 4),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Get started',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const OwnerSetupScreen()),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The real Fulus mark (assets/branding/fulus_mark_transparent.png),
/// composed on a rounded [AppColors.primaryOf] tile the same way the
/// master logo file itself pairs the mark with the brand teal — used
/// here rather than a generic launcher-style icon, since Volume 3 opens
/// this exact step with "The Play Store listing and app icon carry the
/// entire first impression... the icon and name must read clearly."
class _Mark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Image.asset('assets/branding/fulus_mark_transparent.png'),
    );
  }
}
