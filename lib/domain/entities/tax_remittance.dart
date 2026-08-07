/// Volume 8, Taxes: "tax collected, by period... An owner can mark a
/// period as remitted." See tables.dart's `TaxRemittances` doc comment
/// for the confirmed "100% Bible-only, no backend tracking at all"
/// status. Decision 28's own boundary applies directly: "the app
/// tracks what's owed; it does not file anything" — this entity is
/// purely a record that an owner dealt with a period, not a
/// computation of what was owed (that's `FinanceStatsRepository.
/// getTaxCollected`'s job, reading straight from `Sale.tax`).
class TaxRemittance {
  const TaxRemittance({
    required this.localId,
    required this.locationId,
    required this.periodStart,
    required this.periodEnd,
    required this.amountRemitted,
    this.referenceNumber,
    this.note,
    required this.remittedAt,
  });

  final String localId;
  final String locationId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amountRemitted;

  /// Whatever the tax authority's own receipt/confirmation number is —
  /// freeform, this app has no relationship with any tax authority to
  /// validate it against.
  final String? referenceNumber;

  final String? note;
  final DateTime remittedAt;
}

class TaxRemittanceDraft {
  const TaxRemittanceDraft({
    required this.locationId,
    required this.periodStart,
    required this.periodEnd,
    required this.amountRemitted,
    this.referenceNumber,
    this.note,
  });

  final String locationId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amountRemitted;
  final String? referenceNumber;
  final String? note;

  TaxRemittance toEntity({required String localId}) {
    return TaxRemittance(
      localId: localId,
      locationId: locationId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      amountRemitted: amountRemitted,
      referenceNumber: referenceNumber,
      note: note,
      remittedAt: DateTime.now(),
    );
  }
}
