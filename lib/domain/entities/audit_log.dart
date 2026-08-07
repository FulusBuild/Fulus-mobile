/// The domain-facing shape of one audit trail entry. Named
/// AuditLogEntry, not AuditLog, specifically to avoid colliding with
/// Drift's generated AuditLogRow (tables.dart) at import sites that need
/// both.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.userId,
    required this.action,
    required this.module,
    required this.recordId,
    required this.details,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String action;
  final String module;
  final String? recordId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
}
