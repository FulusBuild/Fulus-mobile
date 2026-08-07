import 'package:drift/drift.dart';

import '../../domain/entities/supplier_ledger_entry.dart';
import '../local/database/database.dart';

SupplierLedgerEntryType _entryTypeFromColumn(String value) {
  return switch (value) {
    'stockPurchaseOnCredit' => SupplierLedgerEntryType.stockPurchaseOnCredit,
    'paymentMade' => SupplierLedgerEntryType.paymentMade,
    _ => throw ArgumentError.value(
        value,
        'entryType',
        'unrecognized supplier ledger entry type stored in the database',
      ),
  };
}

extension SupplierLedgerEntryToCompanion on SupplierLedgerEntry {
  SupplierLedgerEntriesCompanion toDriftCompanion() {
    return SupplierLedgerEntriesCompanion.insert(
      localId: localId,
      supplierLocalId: supplierLocalId,
      entryType: entryType.name,
      amount: amount,
      createdAt: createdAt,
      paymentMethod: Value(paymentMethod),
      note: Value(note),
      stockMovementLocalId: Value(stockMovementLocalId),
    );
  }
}

extension SupplierLedgerEntryRowToDomain on SupplierLedgerEntryRow {
  SupplierLedgerEntry toDomain() {
    return SupplierLedgerEntry(
      localId: localId,
      supplierLocalId: supplierLocalId,
      entryType: _entryTypeFromColumn(entryType),
      amount: amount,
      paymentMethod: paymentMethod,
      note: note,
      stockMovementLocalId: stockMovementLocalId,
      createdAt: createdAt,
    );
  }
}
