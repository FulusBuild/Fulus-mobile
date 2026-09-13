import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/core/theme/app_theme.dart';
import 'package:fulus_mobile/core/ux/consumer_polish.dart';

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
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.label, 'Test action');

    await tester.tap(find.text('Do it'));
    expect(taps, 1);
  });
}
