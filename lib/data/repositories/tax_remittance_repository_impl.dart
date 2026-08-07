import 'package:ulid/ulid.dart';

import '../../domain/entities/tax_remittance.dart';
import '../../domain/repositories/tax_remittance_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'tax_remittance_mapper.dart';

class TaxRemittanceRepositoryImpl implements TaxRemittanceRepository {
  TaxRemittanceRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<TaxRemittance> recordRemittance(TaxRemittanceDraft draft) async {
    if (draft.amountRemitted <= 0) {
      throw ArgumentError.value(
        draft.amountRemitted,
        'amountRemitted',
        'must be > 0',
      );
    }
    if (draft.periodEnd.isBefore(draft.periodStart)) {
      throw ArgumentError('periodEnd must not be before periodStart');
    }

    final remittance = draft.toEntity(localId: Ulid().toString());
    await _db.into(_db.taxRemittances).insert(remittance.toDriftCompanion());
    return remittance;
  }

  @override
  Stream<List<TaxRemittance>> watchRemittances({required String locationId}) {
    final query = _db.select(_db.taxRemittances)
      ..where((r) => r.locationId.equals(locationId))
      ..orderBy([(r) => OrderingTerm.desc(r.remittedAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }
}
