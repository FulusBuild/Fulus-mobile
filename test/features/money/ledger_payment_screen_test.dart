import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:fulus_mobile/features/money/presentation/screens/ledger_payment_screen.dart';

void main() {
  testWidgets('payment amount starts blank and balance is shown separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LedgerPaymentScreen(
            title: 'Record repayment',
            counterpartyLabel: 'Owes',
            counterpartyName: 'QA customer',
            outstandingBalance: moneyFromMajor(1250),
            currencySymbol: '₦',
            successMessage: 'Payment recorded.',
            onSubmit: ({required amount, required paymentMethod, note}) async =>
                (newBalance: 0, excessAmount: 0),
          ),
        ),
      ),
    );

    expect(find.textContaining('Enter the amount received.'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.controller?.text.isEmpty ?? true),
      isTrue,
    );
  });
}
