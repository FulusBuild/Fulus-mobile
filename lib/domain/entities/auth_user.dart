/// The domain-facing "who's logged in" representation — Architecture
/// Section 6, re-scoped by the Architecture Redesign (local Business
/// Engine, no server-issued credentials). Previously this deliberately
/// excluded both JWT tokens as a domain/UI concern (they lived in
/// ApiClient's interceptor and SecureStorage instead); there's simply no
/// token at all now; there's a signed-in local user, full stop, per the
/// plain local-session model this same redesign settled on.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String username;
  final String email;
  final String fullName;
  final AuthRole role;
  final bool isActive;
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
