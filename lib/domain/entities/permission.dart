import 'auth_user.dart';

/// Granular, individually-grantable capabilities for a non-owner login.
///
/// This is deliberately a *separate* concept from [AuthRole]. AuthRole
/// still answers "what preset does this login start from" (and, for
/// `AuthRole.owner`, "is this account structurally exempt from every
/// restriction, no matter what a permissions table says"); Permission
/// answers "can this specific login, right now, do this specific
/// thing." Keeping them apart is what lets an owner hand a Cashier
/// login one extra capability (say, `viewReports`) without having to
/// inflate a fixed role enum with a combinatorial explosion of
/// almost-Cashier, almost-Manager variants every time a shop's real
/// staffing doesn't match either preset exactly.
///
/// `Employee.role` (domain/entities/employee.dart) is a third, still
/// unrelated concept — a free-text HR job title ("Shift Lead", "Junior
/// Cashier") with no enforcement meaning at all. Do not conflate it
/// with either AuthRole or Permission; see that file's own doc comment.
enum Permission {
  /// See the Money tab and its transaction history at all. Without
  /// this, the bottom nav's Money entry is hidden and its routes
  /// redirect away, same as the old hard-coded employee block did.
  viewMoney,

  /// See Home's business-wide notices/quick-actions/activity feed
  /// section, not just their own today's-shift hero figure (Decision
  /// 13's "an employee's Home is their own shift, full stop" still
  /// holds for anyone lacking this).
  viewDashboardStats,

  /// Issue a refund or void a sale without a supervisor's approval PIN.
  /// Without it, the existing `requireOwnerApproval` PIN-sheet flow in
  /// refund_confirm_screen.dart / void_sale_screen.dart /
  /// record_stock_movement_screen.dart still applies — this permission
  /// is what an owner grants a trusted Manager to skip that friction,
  /// same enforcement mechanism, just no longer hard-wired to "is this
  /// literally an owner."
  approveWithoutSupervisor,

  /// Record stock movements beyond a plain sale-driven stock-out —
  /// manual stock-in, adjustments, transfers.
  manageStock,

  /// View the Reports section under More.
  viewReports,

  /// Add, edit, deactivate team members and change their access
  /// (including other people's Permission grants). Deliberately does
  /// NOT let a Manager grant themselves permissions they don't already
  /// have — see PermissionRepository.setPermissions's doc comment.
  manageEmployees,

  /// Business settings, printers, locations, sync — the general
  /// "configure how the business runs" surface under More/Settings.
  manageSettings,

  /// Backup & Restore under Settings — deliberately separate from
  /// manageSettings since restoring a backup is destructive in a way
  /// ordinary settings edits aren't; an owner may trust a Manager with
  /// one but not the other.
  manageBackup,

  /// View the audit log. No screen consumes this yet (see
  /// AuditRepository.getAuditLogs's doc comment) but the permission
  /// exists now so the editor UI and enforcement are ready the day
  /// that screen is built, rather than needing another schema bump.
  viewAuditLog;

  /// Everything, for `AuthRole.owner` — never persisted (owner is
  /// exempt structurally, not via a stored grant; see
  /// PermissionRepository.hasPermission), but useful wherever code
  /// wants a concrete Set<Permission> for "this session can do
  /// anything" without special-casing owner separately.
  static Set<Permission> get all => Permission.values.toSet();

  /// The starting grant applied the moment an owner creates a login
  /// with the given preset role. Purely a *default* — the owner can
  /// add or remove individual permissions immediately afterward from
  /// the employee's detail screen, and later edits never snap back to
  /// this preset. `AuthRole.owner` isn't handled here since owners are
  /// never given a stored grant at all (see hasPermission).
  static Set<Permission> defaultsForRole(AuthRole role) {
    switch (role) {
      case AuthRole.owner:
        return all;
      case AuthRole.manager:
        return {
          Permission.viewMoney,
          Permission.viewDashboardStats,
          Permission.approveWithoutSupervisor,
          Permission.manageStock,
          Permission.viewReports,
        };
      case AuthRole.cashier:
        return {Permission.manageStock};
      case AuthRole.employee:
        // No preset fits — matches the old hard two-role model's
        // employee default (Stock + Sell only, everything else
        // blocked) so existing installs' employee logins keep
        // behaving exactly as before a permissions table existed for
        // them at all.
        return {};
    }
  }
}
