import 'package:drift/drift.dart';

import '../../domain/entities/supplier_ledger_entry.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

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
      serverId: const Value(null),
      supplierLocalId: supplierLocalId,
      locationLocalId: Value(locationLocalId),
      entryType: entryType.name,
      amount: amount,
      createdAt: createdAt,
      updatedAt: createdAt,
      syncStatus: SyncStatus.pending,
      paymentMethod: Value(paymentMethod),
      note: Value(note),
      stockMovementLocalId: Value(stockMovementLocalId),
      cashDrawerShiftLocalId: Value(cashDrawerShiftLocalId),
    );
  }
}

extension SupplierLedgerEntryRowToDomain on SupplierLedgerEntryRow {
  SupplierLedgerEntry toDomain() {
    return SupplierLedgerEntry(
      localId: localId,
      supplierLocalId: supplierLocalId,
      locationLocalId: locationLocalId,
      entryType: _entryTypeFromColumn(entryType),
      amount: amount,
      paymentMethod: paymentMethod,
      note: note,
      stockMovementLocalId: stockMovementLocalId,
      cashDrawerShiftLocalId: cashDrawerShiftLocalId,
      createdAt: createdAt,
    );
  }
}
