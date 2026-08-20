import 'package:fulus_mobile/core/onboarding/onboarding_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors test/sync/sync_config_test.dart's own pattern —
/// SharedPreferences.setMockInitialValues is the package's standard
/// testing utility, no platform channel needed once set.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('both flags default to true on a fresh install — the deliberate '
      'inverse of SyncConfig, so a pre-existing business never sees '
      'onboarding retroactively', () async {
    final state = await OnboardingState.load();
    expect(state.hasSeenFirstRunPrompt, isTrue);
    expect(state.hasCelebratedFirstSale, isTrue);
  });

  test('armFirstRun flips both flags to false together', () async {
    final state = await OnboardingState.load();
    await state.armFirstRun();
    expect(state.hasSeenFirstRunPrompt, isFalse);
    expect(state.hasCelebratedFirstSale, isFalse);
  });

  test('markFirstRunPromptSeen only affects that one flag', () async {
    final state = await OnboardingState.load();
    await state.armFirstRun();
    await state.markFirstRunPromptSeen();
    expect(state.hasSeenFirstRunPrompt, isTrue);
    expect(state.hasCelebratedFirstSale, isFalse);
  });

  test('markFirstSaleCelebrated only affects that one flag', () async {
    final state = await OnboardingState.load();
    await state.armFirstRun();
    await state.markFirstSaleCelebrated();
    expect(state.hasCelebratedFirstSale, isTrue);
    expect(state.hasSeenFirstRunPrompt, isFalse);
  });

  test('both flags persist across a fresh OnboardingState.load()', () async {
    final first = await OnboardingState.load();
    await first.armFirstRun();
    await first.markFirstRunPromptSeen();

    final second = await OnboardingState.load();
    expect(second.hasSeenFirstRunPrompt, isTrue);
    expect(second.hasCelebratedFirstSale, isFalse);
  });

  group('guided walkthrough', () {
    test('not started on a fresh install, independent of the two flags above', () async {
      final state = await OnboardingState.load();
      expect(state.walkthroughStep, isNull);
      expect(state.walkthroughNotStarted, isTrue);
      expect(state.walkthroughCompleted, isFalse);
      expect(state.walkthroughSkippedSteps, isEmpty);
      // Advancing the walkthrough doesn't touch the older, separate flags.
      expect(state.hasSeenFirstRunPrompt, isTrue);
      expect(state.hasCelebratedFirstSale, isTrue);
    });

    test('advanceWalkthroughTo moves the current step forward', () async {
      final state = await OnboardingState.load();
      await state.advanceWalkthroughTo(OnboardingStep.businessSetup);
      expect(state.walkthroughStep, OnboardingStep.businessSetup);
      expect(state.walkthroughNotStarted, isFalse);
      expect(state.walkthroughCompleted, isFalse);
    });

    test('reaching OnboardingStep.completion is the only completion signal', () async {
      final state = await OnboardingState.load();
      await state.advanceWalkthroughTo(OnboardingStep.verification);
      expect(state.walkthroughCompleted, isFalse);
      await state.advanceWalkthroughTo(OnboardingStep.completion);
      expect(state.walkthroughCompleted, isTrue);
    });

    test('skipping a step records it without affecting the current step', () async {
      final state = await OnboardingState.load();
      await state.advanceWalkthroughTo(OnboardingStep.essentialSettings);
      await state.skipWalkthroughStep(OnboardingStep.essentialSettings);
      expect(state.walkthroughSkippedSteps, {OnboardingStep.essentialSettings});
      expect(state.walkthroughStep, OnboardingStep.essentialSettings);
    });

    test('skipped steps accumulate rather than replace each other', () async {
      final state = await OnboardingState.load();
      await state.skipWalkthroughStep(OnboardingStep.firstProduct);
      await state.skipWalkthroughStep(OnboardingStep.navigationIntro);
      expect(state.walkthroughSkippedSteps, {
        OnboardingStep.firstProduct,
        OnboardingStep.navigationIntro,
      });
    });

    test('skipping the same step twice is a no-op, not a duplicate', () async {
      final state = await OnboardingState.load();
      await state.skipWalkthroughStep(OnboardingStep.verification);
      await state.skipWalkthroughStep(OnboardingStep.verification);
      expect(state.walkthroughSkippedSteps, {OnboardingStep.verification});
    });

    test('step and skipped-set both persist across a fresh OnboardingState.load()', () async {
      final first = await OnboardingState.load();
      await first.advanceWalkthroughTo(OnboardingStep.firstSale);
      await first.skipWalkthroughStep(OnboardingStep.navigationIntro);

      final second = await OnboardingState.load();
      expect(second.walkthroughStep, OnboardingStep.firstSale);
      expect(second.walkthroughSkippedSteps, {OnboardingStep.navigationIntro});
    });

    test('isSkippable matches the spec: required and terminal steps are not', () {
      expect(OnboardingStep.welcome.isSkippable, isFalse);
      expect(OnboardingStep.businessSetup.isSkippable, isFalse);
      expect(OnboardingStep.firstSale.isSkippable, isFalse);
      expect(OnboardingStep.completion.isSkippable, isFalse);
      expect(OnboardingStep.essentialSettings.isSkippable, isTrue);
      expect(OnboardingStep.firstProduct.isSkippable, isTrue);
      expect(OnboardingStep.navigationIntro.isSkippable, isTrue);
      expect(OnboardingStep.verification.isSkippable, isTrue);
    });
  });
}
