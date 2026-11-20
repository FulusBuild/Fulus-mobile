import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/shared/widgets/fulus_text_field.dart';

void main() {
  testWidgets('obscured fields mask text and disable keyboard suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FulusTextField(
            label: 'Password',
            obscureText: true,
            controller: TextEditingController(text: 'secret-value'),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.obscuringCharacter, '•');
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
  });
}
