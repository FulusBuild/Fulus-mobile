import '../entities/report.dart';

/// Stage 12 (Reports half). One method per category, each taking the
/// already-resolved [ReportPeriod] (see ReportsEngine.resolvePeriod) so
/// this repository never has to reason about "this week" vs "custom
/// range" itself — only fetch rows for a concrete [start, end].
abstract class ReportsRepository {
  Future<SalesReport> getSalesReport(ReportPeriod period);
  Future<InventoryReport> getInventoryReport();
  Future<CustomerReport> getCustomerReport(ReportPeriod period);
  Future<FinanceReport> getFinanceReport(ReportPeriod period);
  Future<EmployeeReport> getEmployeeReport(ReportPeriod period);
}
