import 'package:drift/drift.dart';

import '../../domain/entities/income_record.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension IncomeRecordToCompanion on IncomeRecord {
  IncomeRecordsCompanion toDriftCompanion() {
    return IncomeRecordsCompanion.insert(
      localId: localId,
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      locationId: locationId,
      notes: Value(notes),
      deletedAt: const Value(null),
    );
  }
}

extension IncomeRecordRowToDomain on IncomeRecordRow {
  IncomeRecord toDomain() {
    return IncomeRecord(
      localId: localId,
      serverId: serverId,
      locationId: locationId,
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
