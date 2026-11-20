import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/features/money/presentation/widgets/customer_duplicate_warning.dart';

void main() {
  testWidgets('shows duplicate customer advisory and server-provided detail', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerDuplicateWarning(
            message: 'A customer already uses this phone number.',
          ),
        ),
      ),
    );

    expect(find.text('Possible duplicate customer: A customer already uses this phone number.'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
