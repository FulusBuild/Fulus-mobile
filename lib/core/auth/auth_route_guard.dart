import '../../domain/entities/auth_user.dart';

/// Keeps the employee email/password entry route available only while no
/// local identity is active. A signed-in user must use the identity-switch
/// flow; opening `/login` would let its failed-login cleanup clear the active
/// local session.
String? redirectSignedInUserFromLogin({
  required AuthUser? user,
  required String matchedLocation,
}) {
  if (user != null && matchedLocation == '/login') return '/';
  return null;
}
