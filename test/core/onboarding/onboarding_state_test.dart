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
}
