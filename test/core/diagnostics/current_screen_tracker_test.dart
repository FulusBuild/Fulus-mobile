import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/diagnostics/capture/current_screen_tracker.dart';

void main() {
  test('keeps the current screen aligned with the active shell branch', () {
    final homeObserver = CurrentScreenObserver(branch: 0);
    final stockObserver = CurrentScreenObserver(branch: 1);

    homeObserver.didPush(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'home'),
        builder: (_) => const SizedBox(),
      ),
      null,
    );
    CurrentScreenTracker.activateBranch(0);
    expect(CurrentScreenTracker.current, 'home');

    stockObserver.didPush(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'stockProductDetail'),
        builder: (_) => const SizedBox(),
      ),
      null,
    );
    expect(CurrentScreenTracker.current, 'home');

    CurrentScreenTracker.activateBranch(1);
    expect(CurrentScreenTracker.current, 'stockProductDetail');
  });
}
