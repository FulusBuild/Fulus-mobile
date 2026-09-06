import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/location.dart';
import '../../../../shared/widgets/widgets.dart';
import 'identity_picker_screen.dart';
import 'owner_setup_screen.dart';

/// Shown by [AuthGateScreen] (via `resolveAuthGateStage` in
/// core/onboarding/onboarding_routing.dart) for the one local state the
/// rest of onboarding has no other way out of: a business
/// (`BusinessSettingsRepository.hasBeenConfigured()` true) with no
/// matching owner account on this device
/// (`AuthRepository.hasAnyOwnerAccount()` false) — an onboarding
/// attempt interrupted between the two halves of first-run setup in an
/// earlier session, or a partial local data restore. Whatever the exact
/// cause, the recovery choices are the same.
///
/// Requirement 3's "professional recovery experience" — Welcome back,
/// what was found, three explicit choices, nothing silent:
/// - **Continue Setup**: create the missing owner account, then land
///   straight in the app — [OwnerSetupScreen] in
///   `linkToExistingBusiness` mode, since the business itself doesn't
///   need re-doing.
/// - **Use Existing Business**: skip straight to the identity picker,
///   for the case a working account does exist and this screen's
///   detection is simply wrong (e.g. a Sessions row expired but the
///   Users row is fine) — [IdentityPickerScreen] itself is the safe way
///   to find out either way.
/// - **Start Fresh**: wipes every local business record
///   (`BusinessSettingsRepository.clearLocalBusinessData()`) — gated
///   behind [showFulusConfirmDialog] per Component Library 5.9, never
///   on a single tap, and names the business by name in the prompt
///   rather than a generic "are you sure."
class RestoreProgressScreen extends ConsumerStatefulWidget {
  const RestoreProgressScreen({super.key});

  @override
  ConsumerState<RestoreProgressScreen> createState() => _RestoreProgressScreenState();
}

class _RestoreProgressScreenState extends ConsumerState<RestoreProgressScreen> {
  // Cached once, same reasoning as every other auth screen's own
  // late-final future (AuthGateScreen, _ShellGate) — avoids re-querying
  // the database and flickering back to loading on every rebuild.
  late final Future<(BusinessProfile?, List<Location>)> _detectedFuture = _load();
  bool _clearing = false;

  Future<(BusinessProfile?, List<Location>)> _load() async {
    // .first, not a live subscription — this screen's job is a single
    // point-in-time snapshot to show the owner before they choose,
    // not a reactive view; matches the one-shot reads
    // AuthGateScreen/_ShellGate already do for the same purpose.
    final profile = await ref.read(businessSettingsRepositoryProvider).watchSettings().first;
    final locations = await ref.read(locationRepositoryProvider).watchLocations().first;
    return (profile, locations);
  }

  Future<void> _startFresh(BusinessProfile? profile) async {
    final businessName = profile?.businessName ?? 'this business';
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Start fresh?',
      message: 'This permanently deletes "$businessName" and all its local data — '
          'products, sales, customers, everything on this device. This cannot be undone.',
      confirmLabel: 'Delete and start fresh',
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      await ref.read(businessSettingsRepositoryProvider).clearLocalBusinessData();
      if (!mounted) return;
      // Bug fix: this used to push a bare GetStartedScreen() here,
      // orphaned from AuthGateScreen's own re-evaluation — see
      // ScreenExit.closeScreenOr's own doc comment on the "phantom dead
      // end" that produces the moment anything is pushed on top of it
      // and later closed (exactly what OwnerSetupScreen's "Continue
      // Setup" does next). context.go('/') routes back through
      // go_router's own '/' route (AuthGateScreen, per router.dart),
      // which re-runs stage detection from scratch and shows
      // GetStartedScreen the same way a genuine first launch does —
      // same fix as BackupRestoreDecisionScreen's own Start Fresh.
      context.go('/');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: FutureBuilder<(BusinessProfile?, List<Location>)>(
              future: _detectedFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: FulusLoadingIndicator(),
                  );
                }
                final (profile, locations) = snapshot.data!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We found an existing business setup on this device.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FulusCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetectedRow(
                            label: 'Business',
                            value: profile?.businessName ?? 'Unknown business',
                          ),
                          // Business type isn't stored anywhere in the
                          // BusinessSettings table (it only ever feeds
                          // one-time VAT defaults at creation, per
                          // BusinessCategoryDefaults) — "if available"
                          // is never true today, so it's correctly
                          // absent here rather than showing a made-up
                          // value.
                          if (locations.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _DetectedRow(label: 'Location', value: locations.first.name),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FulusButton(
                      label: 'Continue Setup',
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const OwnerSetupScreen(linkToExistingBusiness: true),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FulusButton(
                      label: 'Use Existing Business',
                      variant: FulusButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const IdentityPickerScreen()),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FulusButton(
                      label: 'Start Fresh',
                      variant: FulusButtonVariant.text,
                      loading: _clearing,
                      loadingLabel: 'Clearing',
                      onPressed: _clearing ? null : () => _startFresh(profile),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectedRow extends StatelessWidget {
  const _DetectedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
