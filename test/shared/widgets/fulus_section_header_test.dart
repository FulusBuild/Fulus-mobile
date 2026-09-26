import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/theme/app_theme.dart';
import '../../../lib/shared/widgets/fulus_section_header.dart';

void main() {
  testWidgets('section header stacks action on narrow screens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.0),
          ),
          child: const Scaffold(
            body: FulusSectionHeader(
              title: 'Recent activity',
              action: 'See all',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section header stacks action for large text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const Scaffold(
            body: FulusSectionHeader(
              title: 'Recent activity',
              action: 'See all',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
