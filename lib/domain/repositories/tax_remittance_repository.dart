import '../entities/tax_remittance.dart';

/// No sync methods at all — see the `TaxRemittance` entity's own doc
/// comment for why this is entirely local record-keeping.
abstract class TaxRemittanceRepository {
  Future<TaxRemittance> recordRemittance(TaxRemittanceDraft draft);

  /// Reverse-chronological by [TaxRemittance.remittedAt] — matches every
  /// other history view in this codebase.
  Stream<List<TaxRemittance>> watchRemittances({required String locationId});
}
