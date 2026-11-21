import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/theme/app_theme.dart';
import 'package:fulus_mobile/features/onboarding/presentation/screens/add_first_product_screen.dart';
import 'package:fulus_mobile/features/onboarding/presentation/screens/first_sale_intro_screen.dart';
import 'package:fulus_mobile/features/onboarding/presentation/screens/completion_screen.dart';

void main() {
  testWidgets('catalog step works for new and already restored businesses', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AddFirstProductScreen(),
        ),
      ),
    );

    expect(find.text('Set up your catalog'), findsOneWidget);
    expect(find.text('Continue without adding products'), findsOneWidget);
    expect(find.text('Add your first product'), findsNothing);
  });

  testWidgets('sale introduction does not claim the first sale or product', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const FirstSaleIntroScreen(),
        ),
      ),
    );

    expect(find.text('Ready to record a sale?'), findsOneWidget);
    expect(find.text('Open Sell'), findsOneWidget);
    expect(find.text("You've created your first product."), findsNothing);
    expect(find.text('Make your first sale'), findsNothing);
  });

  testWidgets('completion copy does not claim optional setup actions happened', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light, home: const CompletionScreen()),
      ),
    );

    expect(find.text('Your business is set up. Add products and record sales whenever you’re ready.'), findsOneWidget);
    expect(find.textContaining('your first product is in inventory'), findsNothing);
  });
}
