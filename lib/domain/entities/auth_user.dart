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

/// The Bible's actual two-role product model (Volume 9), not the
/// backend's four-value admin/manager/staff/cashier vocabulary. Was
/// previously kept as a plain String specifically because "nothing in
/// this phase branches on role yet" and the backend was the vocabulary's
/// source of truth; both of those reasons are gone now — the local
/// Business Engine's own permission checks are the actual enforcement
/// (see failure.dart's AuthFailure.forbidden doc comment) and there's no
/// external system left to defer the vocabulary to. A real enum,
/// exhaustively switched on wherever a permission check happens, is
/// strictly safer than a String that could silently be any value.
enum AuthRole {
  owner,
  employee,
}
