import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/features/stock/application/stock_providers.dart';
import 'package:fulus_mobile/features/stock/presentation/screens/add_edit_product_screen.dart';
import 'package:fulus_mobile/shared/widgets/fulus_text_field.dart';
import 'package:fulus_mobile/shared/widgets/fulus_button.dart';

Finder inputFor(WidgetTester tester, String label) {
  final field = find.byWidgetPredicate(
    (widget) => widget is FulusTextField && widget.label == label,
  );
  return find.descendant(of: field, matching: find.byType(TextField));
}

void main() {
  testWidgets('invalid cost, threshold and starting stock show field errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
          suppliersProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: AddEditProductScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(inputFor(tester, 'Name'), 'Test item');
    await tester.enterText(inputFor(tester, 'Price'), '12.50');
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.enterText(inputFor(tester, 'Cost price'), 'not money');
    await tester.enterText(inputFor(tester, 'Low stock threshold'), '-1');
    await tester.enterText(inputFor(tester, 'Starting stock'), '1.5');
    expect(
      tester.widget<TextField>(inputFor(tester, 'Cost price')).controller!.text,
      'not money',
    );
    expect(
      tester
          .widget<TextField>(inputFor(tester, 'Low stock threshold'))
          .controller!
          .text,
      '-1',
    );
    expect(
      tester
          .widget<TextField>(inputFor(tester, 'Starting stock'))
          .controller!
          .text,
      '1.5',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FulusButton, 'Add product');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid cost of 0 or more.'), findsOneWidget);
    expect(find.text('Enter a whole number of 0 or more.'), findsNWidgets(2));
  });
}
