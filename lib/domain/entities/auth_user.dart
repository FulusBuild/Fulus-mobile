/// The domain-facing "who's logged in" representation — Architecture
/// Section 6, re-scoped by the Architecture Redesign (local Business
/// Engine, no server-issued credentials). Previously this deliberately
/// excluded both JWT tokens as a domain/UI concern (they lived in
/// ApiClient's interceptor and SecureStorage instead); there's simply no
/// token at all now; there's a signed-in local user, full stop, per the
/// plain local-session model this same redesign settled on.
///
/// username/email nullable as of the onboarding-simplification pass —
/// see tables.dart's Users class doc comment for the full reasoning.
/// Both are null for the common case (a local identity created from a
/// name alone) and only ever populated for a real, portable, future
/// sync credential — never displayed anywhere in this app today (there
/// was never a screen that showed the owner their own username/email
/// to begin with), so a null value here has nothing depending on it
/// rendering as a fallback string.
class AuthUser {
  const AuthUser({
    required this.id,
    this.username,
    this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.hasLoginPin,
  });

  final String id;
  final String? username;
  final String? email;
  final String fullName;
  final AuthRole role;
  final bool isActive;

  /// Whether this identity has a local PIN set yet (AuthRepository.
  /// setOwnLoginPin) — never the PIN or its hash, just whether one
  /// exists. A device's sole local user genuinely has none (nothing to
  /// distinguish them from); the UI uses this to gate "add another
  /// person to this device" behind "set your own PIN first" rather than
  /// AuthRepositoryImpl inventing one on someone's behalf.
  final bool hasLoginPin;
}

/// Was the Bible's original two-role product model (Volume 9): just
/// `owner`/`employee`, with `employee` a single fixed permission
/// bundle. `manager` and `cashier` are added presets, not a return to
/// the backend's old four-value admin/manager/staff/cashier vocabulary
/// — the actual enforcement is no longer "which of these four values is
/// this," it's the granular grant in domain/entities/permission.dart's
/// `Permission` set (see PermissionRepository). AuthRole's job now is
/// narrower than it used to be: (a) `owner` remains the one
/// structurally-exempt value that no permissions table can ever
/// restrict (every `hasPermission` check special-cases it first,
/// deliberately never by checking a stored grant), and (b) every other
/// value is just the *starting* permission bundle a login gets the
/// moment it's created (`Permission.defaultsForRole`) — after that,
/// the owner can add or remove individual permissions freely, and the
/// login's actual capabilities live in the permissions table, not in
/// which of these four names it was assigned.
///
/// `employee` is kept, not removed, for backward compatibility: every
/// login created before this enum grew `manager`/`cashier` already has
/// `employee` persisted (Users.role is a `textEnum`, stored by name),
/// and it remains a legitimate fourth choice for a login that doesn't
/// fit either preset — it defaults to the old hard-coded employee
/// bundle (Stock + Sell only) rather than to Cashier's or Manager's.
///
/// Still a real enum rather than a String, for the same reason as
/// before — see failure.dart's AuthFailure.forbidden doc comment.
/// Note this codebase's existing AuthRole call sites were all plain
/// `== AuthRole.owner` / `!= AuthRole.owner` checks, not exhaustive
/// switches, when `manager`/`cashier` were added here — so unlike
/// Permission.defaultsForRole's switch (which the compiler forced to
/// handle both new values), those call sites needed a manual audit,
/// not a compiler error, to confirm each one still does the right
/// thing for a Manager or Cashier login. That audit is what changed
/// each of them from "is this literally an owner" to a real permission
/// check wherever the two now mean different things.
enum AuthRole {
  owner,
  employee,
  manager,
  cashier,
}
