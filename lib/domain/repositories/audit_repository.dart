import '../entities/audit_log.dart';
import '../entities/auth_user.dart';

/// Mirrors backend/app/services/audit_service.py's two functions
/// exactly (verified directly against the actual module): log() and
/// get_audit_logs(). Kept as its own repository, not folded into
/// AuthRepository, because it isn't an auth concern that happens to
/// also get called elsewhere — audit_service.log's real call sites
/// (verified directly, 55 of them) span every module in the backend:
/// Sales, Inventory, Finance, Employees, POS, Backup, Imports,
/// Customers, and Auth alike. Each of those Dart equivalents will
/// depend on this same interface as they get built in later stages —
/// this stage only has Auth (Stage 2) actually calling it yet, since
/// nothing else exists in Dart to call it from.
abstract class AuditRepository {
  /// Records one audit entry. Per the backend's own design rule, stated
  /// verbatim in its module docstring and preserved here unchanged: this
  /// must NEVER throw — a failed audit write must never fail the
  /// caller's actual action. AuditRepositoryImpl catches everything
  /// internally; nothing a caller needs to handle.
  Future<void> log({
    String? userId,
    required String action,
    required String module,
    String? recordId,
    Map<String, dynamic>? details,
  });

  /// Owner-only by default (mirrors the backend's
  /// require_role(UserRole.ADMIN) on GET /api/auth/audit-log exactly —
  /// Owner is this app's equivalent of that role). Takes the caller's
  /// own role explicitly rather than this repository holding a
  /// reference to AuthRepository to look it up itself — AuthRepositoryImpl
  /// already depends on AuditRepository (to log login/logout/account-
  /// creation events), so the reverse dependency would make the two
  /// impossible to construct at all. The enforcement itself doesn't
  /// move: this method still throws AuthFailure.forbidden() itself if
  /// [requestingRole] isn't owner and [hasAuditPermission] isn't true —
  /// it just isn't the one looking either up.
  ///
  /// [hasAuditPermission] is the caller-computed result of
  /// `PermissionRepository.hasPermission(..., permission:
  /// Permission.viewAuditLog)` — this repository doesn't take a
  /// PermissionRepository dependency itself for the same circularity
  /// reason [requestingRole] isn't looked up here either: a future
  /// PermissionRepositoryImpl that ever needed to audit-log a
  /// permission change would create exactly the cycle this parameter
  /// shape avoids. Defaults to false so any existing call built before
  /// Roles & Permissions (schemaVersion 10) keeps its old owner-only
  /// behavior unchanged.
  ///
  /// No total-count/pagination-metadata return yet (the backend's own
  /// paginate() helper provides one) — deliberately deferred, not
  /// forgotten: no screen exists yet to consume it (features/ doesn't
  /// exist), so there's nothing real to size that decision against yet.
  Future<List<AuditLogEntry>> getAuditLogs({
    required AuthRole requestingRole,
    bool hasAuditPermission = false,
    String? module,
    String? userId,
    int page = 1,
    int pageSize = 50,
  });
}
