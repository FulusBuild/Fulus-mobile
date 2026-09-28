import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fulus_mobile/app/restore_restart_gate.dart';

void main() {
  testWidgets('blocks business use after a restore until restart', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RestoreRestartGate(
            child: Text('business workspace'),
          ),
        ),
      ),
    );

    expect(find.text('business workspace'), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);

    final context = tester.element(find.byType(RestoreRestartGate));
    ProviderScope.containerOf(context)
        .read(restoreRestartStateProvider)
        .requireRestart();
    await tester.pump();

    expect(find.text('business workspace'), findsOneWidget);
    expect(find.text('Restore complete'), findsOneWidget);
    expect(find.text('Close Fulus'), findsOneWidget);
  });
}
