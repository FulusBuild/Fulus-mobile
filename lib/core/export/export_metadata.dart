/// The metadata block your brief asked every export to carry: "business
/// name, report name, date range, generated date/time, currency,
/// applied filters, summary totals." Deliberately separate from the
/// summary totals themselves — those are just more rows in the same
/// [ExportService.export] call this rides alongside, not a second thing
/// this class needs to know how to format.
class ExportMetadata {
  const ExportMetadata({
    required this.businessName,
    required this.reportName,
    required this.dateRangeLabel,
    required this.generatedAt,
    required this.currencySymbol,
    this.appliedFilters = const [],
  });

  final String businessName;
  final String reportName;

  /// Already human-readable ("1 Jan – 31 Jan 2026", "Today") — the
  /// caller's own period-formatting logic, not reformatted here.
  final String dateRangeLabel;
  final DateTime generatedAt;
  final String currencySymbol;

  /// Already human-readable ("Cashier: Amaka Okafor"), one per active
  /// filter — empty when the report has none active, not padded out
  /// with "All" placeholders for filters the caller didn't apply.
  final List<String> appliedFilters;
}
