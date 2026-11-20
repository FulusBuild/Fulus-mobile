import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_routing.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../shared/widgets/widgets.dart';
import 'backup_restore_decision_screen.dart';
import 'get_started_screen.dart';
import 'identity_picker_screen.dart';
import 'restore_progress_screen.dart';

/// Decides which first-run experience to show — resolved through
/// [resolveAuthGateStage] (core/onboarding/onboarding_routing.dart)
/// rather than the single inline `hasAnyOwnerAccount` check this screen
/// used before that file existed.
class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  // Cache the startup future so rebuilds do not repeat the local checks.
  late Future<(bool, bool, bool, bool)> _stageInputsFuture = _loadStageInputs();
  bool _continueWithoutBackup = false;

  Never _startupFailure(String phase, Object error) {
    throw StateError('STARTUP_${phase}_FAILED: ${error.runtimeType}: $error');
  }

  Future<(bool, bool, bool, bool)> _loadStageInputs() async {
    late final bool hasOwnerAccount;
    try {
      hasOwnerAccount = await ref
          .read(authRepositoryProvider)
          .hasAnyOwnerAccount();
    } catch (error) {
      _startupFailure('AUTH_CHECK', error);
    }

    late final bool businessConfigured;
    try {
      businessConfigured = await ref
          .read(businessSettingsRepositoryProvider)
          .hasBeenConfigured();
    } catch (error) {
      _startupFailure('BUSINESS_CHECK', error);
    }

    // A cross-device employee installation legitimately has no local Owner
    // row. It still has a real local identity and must land on the identity
    // picker rather than being treated as a fresh owner install.
    final hasAnyLocalIdentity =
        (await ref
                .read(databaseProvider)
                .select(ref.read(databaseProvider).users)
                .get())
            .isNotEmpty;
    final hasAnySignInIdentity = hasOwnerAccount || hasAnyLocalIdentity;

    // Durable-backup discovery is best-effort. It is useful for detecting
    // a backup that survived an uninstall, but it must never prevent a
    // fresh install from reaching onboarding. The native MediaStore call
    // is bounded. A timeout/error is surfaced as an unknown state so it cannot be mistaken for no backup.
    final backupRepo = ref.read(backupRepositoryProvider);
    var hasDetectedBackup = false;
    var backupDiscoveryFailed = false;
    if (!hasOwnerAccount && !businessConfigured) {
      try {
        hasDetectedBackup = (await backupRepo.listBackups()).isNotEmpty;
        if (!hasDetectedBackup) {
          hasDetectedBackup =
              (await backupRepo.findDurableBackup().timeout(
                const Duration(seconds: 3),
              )) !=
              null;
        }
      } on TimeoutException {
        backupDiscoveryFailed = true;
      } catch (_) {
        backupDiscoveryFailed = true;
      }
    }

    final stage = resolveAuthGateStage(
      hasOwnerAccount: hasAnySignInIdentity,
      businessConfigured: businessConfigured,
      hasDetectedBackup: hasDetectedBackup,
      backupDiscoveryFailed: backupDiscoveryFailed,
    );

    if (stage == AuthGateStage.needsAccountCreation) {
      try {
        final onboardingState = ref.read(onboardingStateProvider);
        if (onboardingState.walkthroughNotStarted) {
          await onboardingState.advanceWalkthroughTo(OnboardingStep.welcome);
          ref.read(walkthroughStepProvider.notifier).state =
              OnboardingStep.welcome;
        }
      } catch (error) {
        _startupFailure('ONBOARDING_STATE', error);
      }
    }
    return (
      hasAnySignInIdentity,
      businessConfigured,
      hasDetectedBackup,
      backupDiscoveryFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, bool, bool, bool)>(
      future: _stageInputsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error.toString().replaceFirst(
            'Bad state: ',
            '',
          );
          return FulusScreen(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FulusCard(
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 34,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Fulus could not finish starting.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A startup check failed. Try again, or use the diagnostic below if the problem persists.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FulusActionTile(
                        label: 'Try again',
                        subtitle: 'Run the startup checks again.',
                        icon: Icons.refresh_rounded,
                        onTap: () => setState(
                          () => _stageInputsFuture = _loadStageInputs(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FulusCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Startup diagnostic',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(error),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const FulusScreen(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FulusLoadingIndicator(),
                  SizedBox(height: 12),
                  Text('Checking this device for a saved Fulus backup…'),
                ],
              ),
            ),
          );
        }

        final (
          hasOwnerAccount,
          businessConfigured,
          hasDetectedBackup,
          backupDiscoveryFailed,
        ) = snapshot.data!;
        final stage = resolveAuthGateStage(
          hasOwnerAccount: hasOwnerAccount,
          businessConfigured: businessConfigured,
          hasDetectedBackup: hasDetectedBackup,
          backupDiscoveryFailed:
              backupDiscoveryFailed && !_continueWithoutBackup,
        );
        switch (stage) {
          case AuthGateStage.needsAccountCreation:
            return const GetStartedScreen();
          case AuthGateStage.needsSignIn:
            return const IdentityPickerScreen();
          case AuthGateStage.needsRestoreDecision:
            return const RestoreProgressScreen();
          case AuthGateStage.needsBackupDecision:
            return const BackupRestoreDecisionScreen();
          case AuthGateStage.backupDiscoveryUnavailable:
            return FulusScreen(
              title: 'Couldn’t check for a backup',
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Fulus could not confirm whether this device has a saved backup. Retry the check before starting fresh, or continue without restoring if you are sure you do not need an older business.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FulusButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    onPressed: () => setState(() {
                      _continueWithoutBackup = false;
                      _stageInputsFuture = _loadStageInputs();
                    }),
                  ),
                  const SizedBox(height: 8),
                  FulusButton(
                    label: 'Continue without restoring',
                    variant: FulusButtonVariant.secondary,
                    onPressed: () =>
                        setState(() => _continueWithoutBackup = true),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}
