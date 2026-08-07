import 'package:drift/drift.dart';

import '../../domain/entities/customer_ledger_entry.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

CustomerLedgerEntryType _entryTypeFromColumn(String value) {
  return switch (value) {
    'creditSale' => CustomerLedgerEntryType.creditSale,
    'repayment' => CustomerLedgerEntryType.repayment,
    'refundAdjustment' => CustomerLedgerEntryType.refundAdjustment,
    _ => throw ArgumentError.value(
        value,
        'entryType',
        'unrecognized ledger entry type stored in the database',
      ),
  };
}

extension CustomerLedgerEntryToCompanion on CustomerLedgerEntry {
  CustomerLedgerEntriesCompanion toDriftCompanion({
    required SyncStatus syncStatus,
  }) {
    return CustomerLedgerEntriesCompanion.insert(
      localId: localId,
      customerLocalId: customerLocalId,
      entryType: entryType.name,
      amount: amount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: syncStatus,
      serverId: Value(serverId),
      paymentMethod: Value(paymentMethod),
      note: Value(note),
      saleLocalId: Value(saleLocalId),
    );
  }
}

extension CustomerLedgerEntryRowToDomain on CustomerLedgerEntryRow {
  CustomerLedgerEntry toDomain() {
    return CustomerLedgerEntry(
      localId: localId,
      serverId: serverId,
      customerLocalId: customerLocalId,
      entryType: _entryTypeFromColumn(entryType),
      amount: amount,
      paymentMethod: paymentMethod,
      note: note,
      saleLocalId: saleLocalId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
