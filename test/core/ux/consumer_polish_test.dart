import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/core/theme/app_theme.dart';
import 'package:fulus_mobile/core/theme/design_tokens.dart';
import 'package:fulus_mobile/core/ux/consumer_polish.dart';
import 'package:fulus_mobile/shared/widgets/fulus_action_tile.dart';

void main() {
  testWidgets('FulusPressable exposes button semantics and activates on tap', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FulusPressable(
            semanticsLabel: 'Test action',
            onPressed: () => taps++,
            child: const Text('Do it'),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(FulusPressable));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.label, startsWith('Test action'));

    await tester.tap(find.text('Do it'));
    expect(taps, 1);
  });

  testWidgets('FulusPressable meets Android accessibility tap-target guidance', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: FulusPressable(
              semanticsLabel: 'Save sale',
              onPressed: () {},
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.check),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });

  testWidgets('action tile remains usable at large accessibility text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FulusActionTile(
                icon: Icons.point_of_sale,
                label: 'Customers',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Customers'), findsOneWidget);
  });

  test('Phase 7 interaction tokens keep motion restrained', () {
    expect(AppTouchTarget.minimum, 48);
    expect(AppMotion.fast.inMilliseconds, lessThan(AppMotion.ceiling.inMilliseconds));
    expect(AppMotion.standard.inMilliseconds, lessThanOrEqualTo(AppMotion.ceiling.inMilliseconds));
  });
}
