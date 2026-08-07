/// The sealed failure hierarchy Architecture Section 5's error-mapping
/// table specifies. Originally every variant here was constructed from a
/// mapped Dio exception (ApiClient's interceptor, per the brief's
/// "Error handling" rule under Networking). That's no longer the only
/// source: per the Architecture Redesign (Business Engine ported to
/// Dart, no client/server boundary in the core app), AuthFailure,
/// ValidationFailure, and BusinessRuleFailure are now most often
/// constructed directly by the local Business Engine's own checks —
/// same variants, same shape, new source. NetworkFailure and
/// ApiClient's mapping stay exactly as they were, for the one place
/// they're still genuinely needed: the optional, still-networked Sync
/// layer (LAN/cloud), which is the only part of the app that still
/// crosses a real client/server boundary. Either way, the same rule
/// holds: a raw exception never surfaces to the UI directly.
///
/// This is a sealed class (via the `sealed` modifier, Dart 3+, matching
/// the SDK constraint already set in pubspec.yaml), not an enum, because
/// several variants carry real, distinct payload data (a lockout's
/// retry-after time, a validation failure's field-level detail) that an
/// enum's fixed shape can't express cleanly.
sealed class Failure {
  const Failure(this.message);

  /// Plain-language text, safe to show directly — never a raw HTTP
  /// status code, exception string, or Dart error. Per Volume 14's
  /// Decision 50 (Bible) and Architecture Section 5's table, every
  /// variant below constructs this either directly in Dart, right at
  /// the point the local Business Engine rejects something (the normal
  /// case now — e.g. a ported inventory rule still says "Cannot remove
  /// {quantity} units — only {current_stock} in stock." verbatim, same
  /// wording verified during the original backend audit, just said by
  /// Dart now instead of parsed from a response body), or — for the
  /// Sync layer specifically — from ApiClient's HTTP-error mapping when
  /// there genuinely is a server on the other end of that one call.
  final String message;
}

/// No connectivity, or a request that never reached a server at all.
/// Meaningful only for the Sync layer now — the core app (Business
/// Engine, local database) never makes a network call, so this simply
/// can't occur anywhere outside Sync. Per Architecture Section 5's
/// table: even there, this is explicitly NOT shown as an error in the
/// write path, since the write already succeeded locally — it only
/// ever affects the sync indicator, never blocks the action that
/// triggered it.
final class NetworkFailure extends Failure {
  const NetworkFailure.offline()
      : super('No connection right now — this will sync once you\'re back online.');

  const NetworkFailure.serverUnavailable()
      : super('Having trouble reaching the server. We\'ll keep trying.');
}

sealed class AuthFailure extends Failure {
  const AuthFailure(super.message);

  const factory AuthFailure.sessionExpired() = _SessionExpired;
  const factory AuthFailure.forbidden() = _Forbidden;
  const factory AuthFailure.invalidCredentials() = _InvalidCredentials;
  const factory AuthFailure.accountLocked({required DateTime lockedUntil}) =
      _AccountLocked;
  const factory AuthFailure.accountDeactivated() = _AccountDeactivated;
}

/// Re-scoped for local-only auth (no token to expire anymore): this now
/// means the active local session's own user row stopped being valid
/// out from under it — deactivated, or its access revoked by an owner —
/// while it was still the signed-in session on this device (a real
/// case on a shared till, Volume 9's access-revocation flow), not an
/// expired credential.
final class _SessionExpired extends AuthFailure {
  const _SessionExpired() : super('Please sign in again to continue.');
}

/// The case Architecture Section 5 specifically called out as deserving
/// its own design decision, not a generic mapping — and the Architecture
/// Redesign makes it more load-bearing, not less. Previously a 403 meant
/// the SERVER'S OWN role check rejected the request, and the mobile
/// client's role-gated UI was explicitly "UX over security enforcement
/// the backend genuinely performs" — hiding a button was a courtesy, not
/// the actual gate. With no separate backend left in the core app, the
/// local Business Engine's own permission check IS the actual and only
/// enforcement now: it must genuinely refuse the underlying repository
/// call, not just hide the button that would have triggered it — a
/// direct call bypassing the UI has to be rejected exactly the same way.
/// The message stays generic and calm rather than alarmed, since the
/// most common real-world trigger is still a stale locally-cached
/// permission after a role change synced down from another device, not
/// a genuine access attempt.
final class _Forbidden extends AuthFailure {
  const _Forbidden() : super('You don\'t have permission to do that.');
}

/// BUG FIX (self-audit pass, after Stage 4): auth_service.py's
/// authenticate_user raises this exact, distinct message — verified
/// directly, re-reading the source a second time specifically to check
/// this — for is_active=false, deliberately NOT the same generic
/// "Incorrect username or password" it uses for a wrong password or an
/// unknown username. Whether that asymmetry (revealing that an account
/// exists and was deactivated, vs. staying silent on wrong-password/
/// unknown-username) was itself a deliberate choice or an oversight in
/// the original backend isn't something to second-guess or "improve" by
/// generalizing it into invalidCredentials — faithfully porting what's
/// actually there, asymmetry included, rather than substituting a
/// different security posture nobody asked for.
///
/// This variant didn't exist until this self-audit pass caught that
/// AuthRepositoryImpl.login had no is_active check at all — a real
/// functional gap, not just a missing message: a deactivated account
/// (Volume 9's access-revocation flow) could otherwise still log in
/// successfully with the correct password.
final class _AccountDeactivated extends AuthFailure {
  const _AccountDeactivated() : super('This account has been deactivated.');
}

final class _InvalidCredentials extends AuthFailure {
  const _InvalidCredentials() : super('Incorrect username or password.');
}

/// Mirrors the backend's own account-lockout mechanism exactly (verified
/// directly: MAX_FAILED_LOGIN_ATTEMPTS = 5, LOGIN_LOCKOUT_DURATION = 15
/// minutes, in auth_service.py) — carried over unchanged into the local
/// Business Engine's own login check, since the reasoning (throttle
/// guessing against a credential someone has physical access to) has
/// nothing to do with networking and doesn't go away just because the
/// check moved on-device. Carries the actual lockedUntil time, computed
/// locally at the moment of the 5th failure, so the UI can show a real
/// countdown rather than a vague "try again later".
final class _AccountLocked extends AuthFailure {
  const _AccountLocked({required this.lockedUntil})
      : super('Too many attempts. Try again after the account unlocks.');

  final DateTime lockedUntil;
}

/// Was: a 422, the backend's Pydantic validation rejecting the request.
/// Now: the local Business Engine's own field-level validation (e.g. the
/// ported password-strength rule) rejecting it, same shape — field name
/// -> a plain-language message for that field — just constructed
/// directly at the validation site instead of parsed from a response
/// body. Still carries per-field detail so the UI can show inline
/// errors (Volume 16, Decision 57's form pattern) rather than one
/// generic message for what might be several distinct field problems.
final class ValidationFailure extends Failure {
  const ValidationFailure({
    required this.fieldErrors,
  }) : super('Please check the highlighted fields.');

  final Map<String, String> fieldErrors;
}

/// Was: a 4xx that isn't auth or validation — a deliberate business-rule
/// rejection the backend made on purpose (insufficient stock, a sale
/// total that would go negative, and so on). Now: the same deliberate
/// rejection, made by the ported Dart rule instead. Per Architecture
/// Section 5's table, the original backend message is carried over
/// verbatim wherever a rule is ported — verified during the original
/// audit to already meet the Bible's plain-language bar — not rewritten
/// just because the implementation language changed.
final class BusinessRuleFailure extends Failure {
  const BusinessRuleFailure(super.message);
}

/// Stage 15 (Device Services) — printer/scanner/camera failures. Added
/// to this same file, not a separate one, because `sealed` (Dart 3)
/// requires every direct subtype of a sealed class to live in the same
/// library — the same reason AuthFailure's variants sit here rather than
/// in auth_repository_impl.dart. Follows AuthFailure's exact shape: a
/// sealed intermediate class with const factory constructors, so calling
/// code can exhaustively switch on DeviceFailure specifically when it
/// wants to, or just treat it as a Failure like everything else.
sealed class DeviceFailure extends Failure {
  const DeviceFailure(super.message);

  const factory DeviceFailure.permissionDenied(String message) =
      _PermissionDenied;
  const factory DeviceFailure.connectionFailed(String message) =
      _ConnectionFailed;
  const factory DeviceFailure.printFailed(String message) = _PrintFailed;
  const factory DeviceFailure.notPaired(String message) = _NotPaired;
}

final class _PermissionDenied extends DeviceFailure {
  const _PermissionDenied(super.message);
}

final class _ConnectionFailed extends DeviceFailure {
  const _ConnectionFailed(super.message);
}

final class _PrintFailed extends DeviceFailure {
  const _PrintFailed(super.message);
}

/// Printing (or connecting) attempted with no default printer set at
/// all — distinct from [_ConnectionFailed], which implies a real device
/// was known and reachable-or-not. Volume 3's "Printer Setup — Optional,
/// Not a Blocker" means this is an expected, calm state most businesses
/// hit routinely (Cash/WhatsApp-share/skip, per Volume 5, are the other
/// two equally-weighted receipt options), never itself an error to alarm
/// over — the message a future UI shows for this variant should read
/// that way.
final class _NotPaired extends DeviceFailure {
  const _NotPaired(super.message);
}

/// Deliberately does NOT have a general "UnknownFailure" catch-all with
/// a raw exception's toString() as its message — every code path that
/// constructs a Failure is required to pick a real, considered variant
/// above. An unmapped exception is a defect in the local Business
/// Engine's own error handling (or, for Sync, in ApiClient's
/// interceptor) that should be fixed there, not papered over with a
/// generic fallback that would let a raw stack trace or exception
/// string quietly reach the UI, which is the exact thing this whole
/// hierarchy exists to prevent.
