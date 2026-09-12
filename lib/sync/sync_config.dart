import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stage 16 — Sync Layer Repositioning.
///
/// The single, persisted answer to "is the sync extension switched on
/// right now" — every other change in this stage exists to make this
/// class's [isEnabled] the ONE place that question gets decided, rather
/// than something inferred separately (and inconsistently) at each call
/// site that might otherwise reach for the network.
///
/// Default is `false`. This is not a placeholder waiting to be flipped
/// before release — it's the deliberate reading of HANDOVER's own
/// framing: "Synchronization becomes an extension that can be enabled
/// later," and the Implementation Bible's "Core application must work
/// perfectly with Sync disabled forever." An extension is off until
/// something turns it on; it is not on until something turns it off.
/// Every repository, screen, and background trigger in this codebase
/// has to be correct against that default, not against a future where
/// someone remembered to flip it.
///
/// What this class is deliberately NOT:
/// - It is not a feature flag service (no remote config, no A/B split —
///   there is exactly one flag, decided entirely on-device).
/// - It is not where sync CREDENTIALS or a server URL live — that
///   remains EnvConfig (core/config/env_config.dart) for now, unchanged
///   by this stage. A future Settings screen that lets an owner point
///   Host Mode sync at a specific LAN address is a real, separate
///   feature this class doesn't attempt to anticipate.
///
/// Persisted via shared_preferences rather than the general Drift
/// database (Architecture Section 3) or Keystore-backed secure storage
/// (Section 11) — this is a plain, non-sensitive, single boolean
/// on/off. Putting it in the SQLite file both repositions had it live in
/// AppDatabase would tie this repositioning's own toggle to a schema
/// migration for no benefit; Keystore storage would overstate how
/// sensitive "is background sync switched on" actually is, given
/// SecureStorage's own doc comment on why that treatment is reserved for
/// the refresh token and PIN verifiers specifically.
class SyncConfig extends ChangeNotifier {
  SyncConfig({required SharedPreferences preferences})
      : _preferences = preferences;

  /// Async factory rather than a bare constructor — SharedPreferences
  /// itself is obtained via an async `getInstance()`, and bootstrap.dart
  /// (Architecture Section 1's stated home for all DI/service init)
  /// already awaits several other async setup steps in sequence, so
  /// this fits the same shape rather than introducing a different
  /// initialization pattern just for this one class.
  static Future<SyncConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SyncConfig(preferences: preferences);
  }

  final SharedPreferences _preferences;

  static const _isEnabledKey = 'fulus_sync_enabled';

  /// Synchronous by design, not `Future<bool>` — SharedPreferences reads
  /// its whole backing store into memory once at `getInstance()` (this
  /// is documented, standard behavior for the package, not an
  /// assumption unique to this file) and every subsequent read is a
  /// synchronous, in-memory lookup. This matters concretely: Stage 16's
  /// entire point is that checking "should this network call happen"
  /// must never itself become a reason to await something before
  /// answering — see sync_triggers.dart's own guards, which call this
  /// getter directly, inline, at the top of every method that used to
  /// assume sync was simply always on.
  bool get isEnabled => _preferences.getBool(_isEnabledKey) ?? false;

  /// Flips the toggle. Deliberately does NOT itself start or stop
  /// SyncEngine/SyncTriggers — this class only ever answers "is sync
  /// enabled," it doesn't own the lifecycle of the objects that consult
  /// it. A caller enabling sync for the first time (a future Settings
  /// screen, "Turn on sync") still needs the app restarted, or
  /// bootstrap's sync-activation steps re-run explicitly, for
  /// SyncTriggers.start() to actually begin listening — recorded here
  /// as a known, deliberate limitation of this first pass rather than
  /// solved by, say, this setter reaching sideways into a running
  /// SyncTriggers instance it has no reference to and was never meant
  /// to own.
  Future<void> setEnabled(bool value) async {
    if (isEnabled == value) return;
    await _preferences.setBool(_isEnabledKey, value);
    notifyListeners();
  }
}
