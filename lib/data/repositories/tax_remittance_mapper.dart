import 'package:drift/drift.dart';

import '../../domain/entities/tax_remittance.dart';
import '../local/database/database.dart';

extension TaxRemittanceToCompanion on TaxRemittance {
  TaxRemittancesCompanion toDriftCompanion() {
    return TaxRemittancesCompanion.insert(
      localId: localId,
      locationId: locationId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      amountRemitted: amountRemitted,
      remittedAt: remittedAt,
      referenceNumber: Value(referenceNumber),
      note: Value(note),
    );
  }
}

extension TaxRemittanceRowToDomain on TaxRemittanceRow {
  TaxRemittance toDomain() {
    return TaxRemittance(
      localId: localId,
      locationId: locationId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      amountRemitted: amountRemitted,
      referenceNumber: referenceNumber,
      note: note,
      remittedAt: remittedAt,
    );
  }
}
