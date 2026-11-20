import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/features/more/reports/presentation/screens/reports_screen.dart';
import 'package:fulus_mobile/shared/widgets/fulus_skeleton.dart';

void main() {
  testWidgets(
    'reports loading placeholder lays out inside the page scroll view',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: const [ReportsLoadingSkeleton()]),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FulusCardSkeleton), findsNWidgets(3));
    },
  );
}
