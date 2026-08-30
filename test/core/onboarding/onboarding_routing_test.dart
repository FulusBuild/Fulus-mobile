import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/onboarding/onboarding_routing.dart';
import 'package:fulus_mobile/core/onboarding/onboarding_state.dart';

void main() {
  group('resolveAuthGateStage', () {
    test('no owner, no business -> needsAccountCreation', () {
      expect(
        resolveAuthGateStage(hasOwnerAccount: false, businessConfigured: false, hasDetectedBackup: false),
        AuthGateStage.needsAccountCreation,
      );
    });

    test('owner exists -> needsSignIn regardless of business state', () {
      expect(
        resolveAuthGateStage(hasOwnerAccount: true, businessConfigured: false, hasDetectedBackup: false),
        AuthGateStage.needsSignIn,
      );
      expect(
        resolveAuthGateStage(hasOwnerAccount: true, businessConfigured: true, hasDetectedBackup: false),
        AuthGateStage.needsSignIn,
      );
    });

    test('no owner but a business already exists -> needsRestoreDecision', () {
      expect(
        resolveAuthGateStage(hasOwnerAccount: false, businessConfigured: true, hasDetectedBackup: false),
        AuthGateStage.needsRestoreDecision,
      );
    });

    test('no owner, no business, but a backup file is detected -> needsBackupDecision', () {
      expect(
        resolveAuthGateStage(hasOwnerAccount: false, businessConfigured: false, hasDetectedBackup: true),
        AuthGateStage.needsBackupDecision,
      );
    });

    test('needsRestoreDecision still takes priority over a detected backup', () {
      // Checked in this order deliberately (see resolveAuthGateStage's
      // own doc comment) — an in-progress local setup should never be
      // overridden by an old backup file also sitting on the device.
      expect(
        resolveAuthGateStage(hasOwnerAccount: false, businessConfigured: true, hasDetectedBackup: true),
        AuthGateStage.needsRestoreDecision,
      );
    });
  });

  group('resolvePostSignInStage', () {
    test('business not configured -> resumeBusinessSetup, regardless of the other two inputs', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: false,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.essentialSettings,
        ),
        PostSignInStage.resumeBusinessSetup,
      );
    });

    test('walkthrough mid-flight at essentialSettings -> showEssentialSettings', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.essentialSettings,
        ),
        PostSignInStage.showEssentialSettings,
      );
    });

    test('essentialSettings check takes priority over an unseen first-run prompt', () {
      // Both conditions are true at once right after OwnerSetupScreen
      // arms the walkthrough — essentialSettings must win, not
      // showFirstRunPrompt, or the walkthrough never actually shows.
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.essentialSettings,
        ),
        PostSignInStage.showEssentialSettings,
      );
    });

    test('walkthrough mid-flight at firstProduct -> showAddFirstProduct', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.firstProduct,
        ),
        PostSignInStage.showAddFirstProduct,
      );
    });

    test('walkthrough mid-flight at navigationIntro -> showNavigationIntro', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.navigationIntro,
        ),
        PostSignInStage.showNavigationIntro,
      );
    });

    test('walkthrough at firstSale -> showFirstSaleIntro', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: OnboardingStep.firstSale,
        ),
        PostSignInStage.showFirstSaleIntro,
      );
    });

    test(
      'verification and completion enter the shell directly, never showFirstRunPrompt '
      '(a completed first sale already happened by then — the prompt would be wrong)',
      () {
        expect(
          resolvePostSignInStage(
            businessConfigured: true,
            firstRunPromptSeen: false,
            walkthroughStep: OnboardingStep.verification,
          ),
          PostSignInStage.enterShell,
        );
        expect(
          resolvePostSignInStage(
            businessConfigured: true,
            firstRunPromptSeen: false,
            walkthroughStep: OnboardingStep.completion,
          ),
          PostSignInStage.enterShell,
        );
      },
    );

    test('pre-existing install (walkthroughStep always null) behaves exactly as before', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: false,
          walkthroughStep: null,
        ),
        PostSignInStage.showFirstRunPrompt,
      );
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: true,
          walkthroughStep: null,
        ),
        PostSignInStage.enterShell,
      );
    });

    test('fully done -> enterShell', () {
      expect(
        resolvePostSignInStage(
          businessConfigured: true,
          firstRunPromptSeen: true,
          walkthroughStep: OnboardingStep.completion,
        ),
        PostSignInStage.enterShell,
      );
    });
  });
}
