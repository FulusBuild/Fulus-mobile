/// The sealed failure hierarchy Architecture Section 5's error-mapping
/// table specifies. Every Dio exception gets mapped to one of these
/// before it ever reaches a repository or the UI — per the brief's rule
/// ("Error handling" under Networking) and the architecture document's
/// own statement that a raw exception never surfaces to the UI directly.
///
/// This is a sealed class (via the `sealed` modifier, Dart 3+, matching
/// the SDK constraint already set in pubspec.yaml), not an enum, because
/// several variants carry real, distinct payload data (a lockout's
/// retry-after time, a validation failure's field-level detail) that an
/// enum's fixed shape can't express cleanly.
sealed class Failure {
  const Failure(this.message);

  /// Plain-language text, safe to show directly — never a raw HTTP
  /// status code or exception string. Per Volume 14's Decision 50 (Bible)
  /// and Architecture Section 5's table, every variant below constructs
  /// this from either the backend's own already-plain-language message
  /// (verified directly during the audit — e.g. inventory_service.py's
  /// "Cannot remove {quantity} units — only {current_stock} in stock."
  /// needs no rewriting) or a client-side plain-language default for
  /// cases where the backend genuinely has no message to forward (no
  /// connectivity at all, for instance).
  final String message;
}

/// No connectivity, or a request that never reached the server at all.
/// Per Architecture Section 5's table: this is explicitly NOT shown as
/// an error in the write path, since the write already succeeded
/// locally — it only ever affects the sync indicator, never blocks the
/// action that triggered it.
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
}

final class _SessionExpired extends AuthFailure {
  const _SessionExpired() : super('Please sign in again to continue.');
}

/// The case Architecture Section 5 specifically called out as deserving
/// its own design decision, not a generic mapping: a 403 means the
/// server's OWN role check rejected the request. This is not a bug and
/// not something that "shouldn't happen because the button was hidden" —
/// per Section 5's exact reasoning, the mobile client's role-based UI is
/// UX over security enforcement the backend genuinely performs (verified
/// directly: the role-authorization gaps I closed myself in sales.py,
/// finance.py, employees.py, inventory.py, and customers.py during the
/// prior audit are what make this a real, expected server-side outcome
/// now, not a theoretical one). The message stays generic and calm
/// rather than alarmed, since the far more common real-world trigger is
/// a stale locally-cached role after a permission change synced down
/// from another device, not a genuine access attempt.
final class _Forbidden extends AuthFailure {
  const _Forbidden() : super('You don\'t have permission to do that.');
}

final class _InvalidCredentials extends AuthFailure {
  const _InvalidCredentials() : super('Incorrect username or password.');
}

/// Mirrors the backend's own account-lockout mechanism exactly (verified
/// directly: MAX_FAILED_LOGIN_ATTEMPTS = 5, LOGIN_LOCKOUT_DURATION = 15
/// minutes, in auth_service.py, added during the prior audit). Carries
/// the actual lockedUntil time so the UI can show a real countdown
/// rather than a vague "try again later" — the backend's 429 response
/// includes this, so there's no reason to discard it at the mapping
/// boundary.
final class _AccountLocked extends AuthFailure {
  const _AccountLocked({required this.lockedUntil})
      : super('Too many attempts. Try again after the account unlocks.');

  final DateTime lockedUntil;
}

/// A 422 — the backend's Pydantic validation rejected the request.
/// Carries field-level detail so the UI can show inline errors (Volume
/// 16, Decision 57's form pattern) rather than one generic message for
/// what might be several distinct field problems.
final class ValidationFailure extends Failure {
  const ValidationFailure({
    required this.fieldErrors,
  }) : super('Please check the highlighted fields.');

  /// Field name -> the backend's own message for that field, taken
  /// directly from the 422 response body rather than re-derived
  /// client-side, since the backend's Pydantic error messages are
  /// already the authoritative statement of what's wrong.
  final Map<String, String> fieldErrors;
}

/// A 4xx that isn't auth or validation — a deliberate business-rule
/// rejection the backend made on purpose (insufficient stock, a sale
/// total that would go negative, and so on). Per Architecture Section
/// 5's table, the backend's own message is shown verbatim here, not
/// rewritten, since I verified directly that these messages already
/// satisfy the Bible's plain-language bar.
final class BusinessRuleFailure extends Failure {
  const BusinessRuleFailure(super.message);
}

/// Deliberately does NOT have a general "UnknownFailure" catch-all with
/// a raw exception's toString() as its message — every code path that
/// constructs a Failure is required to pick a real, considered variant
/// above. An unmapped exception is a defect in the mapping logic itself
/// (see ApiClient's interceptor) that should be fixed there, not papered
/// over with a generic fallback that would let a raw stack trace or
/// exception string quietly reach the UI, which is the exact thing this
/// whole hierarchy exists to prevent.
