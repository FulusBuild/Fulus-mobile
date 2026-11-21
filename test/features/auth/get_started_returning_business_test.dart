import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/theme/app_theme.dart';
import 'package:fulus_mobile/features/auth/presentation/screens/get_started_screen.dart';

void main() {
  testWidgets('returning owner welcome preserves local-business choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const GetStartedScreen(returningLocalBusiness: true),
        ),
      ),
    );

    expect(find.text('Welcome back to Fulus.'), findsOneWidget);
    expect(find.text('Continue on this device'), findsOneWidget);
    expect(find.text('Sign in or restore'), findsOneWidget);
    expect(find.text('Create your business'), findsNothing);
    expect(find.text('Continue offline'), findsNothing);
  });
}
