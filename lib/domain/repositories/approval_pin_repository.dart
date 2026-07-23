/// Architecture Section 6 / Bible Volume 9's owner-approval PIN system —
/// the one piece of auth that must work fully offline. Separated from
/// AuthRepository deliberately: this is a genuinely distinct concern
/// (an offline-verifiable, multi-owner credential synced as data,
/// rather than a session token), not a variant of login.
abstract class ApprovalPinRepository {
  /// The owner sets their OWN approval PIN — requires connectivity
  /// (Volume 3's "online for anything that must validate against the
  /// server the first time"), since the resulting hash has to reach the
  /// backend before any OTHER device can sync it down. [userId] must be
  /// the currently-authenticated user's own id; enforced by the backend
  /// (ADMIN-role-gated, and always the caller's own account — there is
  /// no path to set someone else's PIN), not re-checked here.
  Future<void> setOwnApprovalPin({required String userId, required String pin});

  /// Pulls the latest "which owners can approve" dataset from the
  /// backend and replaces the locally-stored set entirely — never
  /// merged, so an admin whose PIN was reset (no longer returned by the
  /// backend) doesn't linger locally as a stale, still-matchable
  /// verifier.
  Future<void> syncApprovalHashes();

  /// Checks [pin] against every locally-synced verifier — fully
  /// offline, no network round-trip, matching Volume 9's explicit
  /// "Approvals... both work fully offline" requirement. Returns the
  /// matching owner's user id, or null if no verifier matches.
  Future<String?> verifyApprovalPin(String pin);
}
