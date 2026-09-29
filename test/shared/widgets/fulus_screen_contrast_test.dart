import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/core/theme/app_theme.dart';
import 'package:fulus_mobile/core/theme/design_tokens.dart';
import 'package:fulus_mobile/shared/widgets/fulus_card.dart';
import 'package:fulus_mobile/shared/widgets/fulus_screen.dart';

void main() {
  testWidgets('dark Fulus workspace gives plain text a readable foreground', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FulusScreen(
          backgroundColor: const Color(0xFF061B3A),
          body: Builder(
            builder: (context) => Text(
              'Workspace text',
              style: TextStyle(color: AppColors.textPrimaryOf(context)),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Workspace text'));
    expect(text.style!.color, Colors.white);
  });

  testWidgets('light cards restore dark text inside a dark workspace', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FulusScreen(
          backgroundColor: const Color(0xFF061B3A),
          body: FulusCard(
            child: Builder(
              builder: (context) => Text(
                'Card text',
                style: TextStyle(color: AppColors.textPrimaryOf(context)),
              ),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Card text'));
    expect(text.style!.color, AppColors.textPrimaryLight);
  });
}
