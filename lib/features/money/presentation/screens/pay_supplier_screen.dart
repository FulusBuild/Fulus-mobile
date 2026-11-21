import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../domain/entities/supplier.dart';
import '../providers/money_providers.dart';
import 'ledger_payment_screen.dart';

/// Volume 8, Decision 26: "Pay Supplier mirrors Record Repayment
/// exactly" — same screen, opposite direction, for [supplier].
class PaySupplierScreen extends ConsumerWidget {
  const PaySupplierScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return LedgerPaymentScreen(
      title: 'Pay supplier',
      counterpartyLabel: 'You owe',
      counterpartyName: supplier.name,
      outstandingBalance: supplier.outstandingBalance,
      currencySymbol: currencySymbol,
      successMessage: 'Payment recorded.',
      paymentHelpText:
          'Cash payments are assigned to the open drawer session at the active location.',
      onSubmit: ({required amount, required paymentMethod, note}) async {
        final locationId = await ref.read(activeLocationIdProvider.future);
        String? cashDrawerShiftLocalId;
        if (paymentMethod.trim().toLowerCase() == 'cash') {
          final shift = await ref
              .read(cashDrawerShiftRepositoryProvider)
              .getActiveShift(locationId: locationId);
          cashDrawerShiftLocalId = shift?.localId;
        }
        final result = await ref
            .read(supplierCreditRepositoryProvider)
            .recordPayment(
              supplierLocalId: supplier.localId,
              amount: amount,
              paymentMethod: paymentMethod,
              note: note,
              locationLocalId: locationId,
              cashDrawerShiftLocalId: cashDrawerShiftLocalId,
            );
        return (
          newBalance: result.newBalance,
          excessAmount: result.excessAmount,
            );
      },
    );
  }
}
