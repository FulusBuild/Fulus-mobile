import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../domain/entities/customer.dart';
import '../providers/money_providers.dart';
import 'ledger_payment_screen.dart';

/// Volume 7's "amount, method, done" repayment action, for [customer].
class RecordRepaymentScreen extends ConsumerWidget {
  const RecordRepaymentScreen({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return LedgerPaymentScreen(
      title: 'Record repayment',
      counterpartyLabel: 'Owes',
      counterpartyName: customer.name,
      outstandingBalance: customer.outstandingBalance,
      currencySymbol: currencySymbol,
      successMessage: 'Repayment recorded.',
      onSubmit: ({required amount, required paymentMethod, note}) async {
        final result = await ref.read(customerCreditRepositoryProvider).recordRepayment(
              customerLocalId: customer.localId,
              amount: amount,
              paymentMethod: paymentMethod,
              note: note,
            );
        return (newBalance: result.newBalance, excessAmount: result.excessAmount);
      },
    );
  }
}
