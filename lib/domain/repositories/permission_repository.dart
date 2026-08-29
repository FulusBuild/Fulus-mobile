import '../entities/auth_user.dart';
import '../entities/permission.dart';

/// The enforcement side of domain/entities/permission.dart's `Permission`
/// enum — backed entirely by the local UserPermissions table
/// (PermissionRepositoryImpl), same local-Business-Engine shape as
/// AuthRepository. See that enum's own doc comment for how this relates
/// to (and deliberately doesn't replace) [AuthRole].
abstract class PermissionRepository {
  /// The exact set of permissions explicitly granted to [userId] — never
  /// includes an implicit "and everything Owner gets" for an Owner
  /// account; callers that need "can this session do X" should call
  /// [hasPermission] instead, which is the one place Owner's structural
  /// exemption is applied. This getter exists for the permission-editor
  /// UI, which needs to know exactly what's stored (to show accurate
  /// checkboxes), not what an owner's own login would resolve to.
  Future<Set<Permission>> getPermissions(String userId);

  /// Whether [userId] — currently holding [role] — can do [permission]
  /// right now. `role == AuthRole.owner` always returns true without
  /// even querying the UserPermissions table: Owner is structurally
  /// exempt from every restriction by design (Volume 9's original
  /// two-role model already made owner permission-proof; this repo
  /// preserves that instead of quietly making "owner" just another
  /// preset a permissions row could theoretically strip). Every other
  /// role is a real lookup against what's actually been granted.
  ///
  /// Takes [role] explicitly rather than looking the user up itself, on
  /// purpose — it keeps this repository a pure permissions store with
  /// no dependency on AuthRepository (which is itself a dependency of
  /// several callers of this method), the same reason
  /// AuditRepository.getAuditLogs takes a plain `requestingRole`
  /// parameter instead of importing AuthRepository — see that method's
  /// own doc comment.
  Future<bool> hasPermission({
    required String userId,
    required AuthRole role,
    required Permission permission,
  });

  /// Replaces [userId]'s entire stored permission set with exactly
  /// [permissions] — not an incremental add/remove, the same
  /// "full replace, caller sends the complete desired state" shape
  /// BusinessSettingsRepository.updateSettings already uses. [grantedBy]
  /// is the acting owner's own user id, recorded on every row for the
  /// audit trail UserPermissions.grantedBy exists for.
  ///
  /// Deliberately takes no stance on WHO is allowed to call this —
  /// PermissionRepositoryImpl enforces nothing about the caller being
  /// an owner, the same division of responsibility AuthRepositoryImpl
  /// already has with the Business Engine's other permission checks:
  /// the presentation layer (the employee detail screen) is the one
  /// place that both knows and enforces "only an owner ever reaches
  /// this editor UI at all," so the enforcement happens once, there,
  /// rather than being duplicated (and risking drifting out of sync)
  /// in this repository too.
  Future<void> setPermissions({
    required String userId,
    required Set<Permission> permissions,
    required String grantedBy,
  });

  /// Called once, at the moment [createEmployeeAccount] (AuthRepository)
  /// creates a brand-new login — seeds its stored grant from
  /// [Permission.defaultsForRole], same [grantedBy] audit trail as
  /// [setPermissions]. Kept as its own method rather than having
  /// callers compute the default set and call [setPermissions]
  /// themselves, so "what a fresh Cashier login starts with" has
  /// exactly one call site to reason about.
  Future<void> seedDefaultsForNewAccount({
    required String userId,
    required AuthRole role,
    required String grantedBy,
  });
}
