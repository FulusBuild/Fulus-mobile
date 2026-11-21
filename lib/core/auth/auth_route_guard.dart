import '../../domain/entities/auth_user.dart';

/// Keeps account-entry routes available only while no local identity is
/// active. A signed-in user must use the identity-switch flow; leaving them
/// on `/login` or `/welcome` can expose stale entry actions or let failed-login
/// cleanup clear the active local session.
String? redirectSignedInUserFromLogin({
  required AuthUser? user,
  required String matchedLocation,
}) {
  if (user != null &&
      (matchedLocation == '/login' || matchedLocation == '/welcome')) {
    return '/';
  }
  return null;
}
