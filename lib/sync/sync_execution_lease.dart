import 'dart:async';
import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../data/local/database/database.dart';

/// Cross-isolate/device-process lease for Cloud Sync.
///
/// Foreground Flutter and WorkManager background execution can both create
/// their own Dart isolate. A normal Dart mutex cannot coordinate those runtimes,
/// so the lease is stored in SQLite, which both runtimes already share.
///
/// The lease is short-lived and renewed while held. A crashed runtime therefore
/// cannot permanently strand synchronization, while a healthy long-running
/// sync cannot expire underneath itself.
class SyncExecutionLease {
  SyncExecutionLease(
    this._db, {
    Duration leaseDuration = const Duration(minutes: 2),
    Duration acquisitionTimeout = const Duration(seconds: 2),
  })  : _leaseDuration = leaseDuration,
        _acquisitionTimeout = acquisitionTimeout,
        _ownerId = Ulid().toString();

  static const String leaseName = 'cloud_sync';

  final AppDatabase _db;
  final Duration _leaseDuration;
  final Duration _acquisitionTimeout;
  final String _ownerId;
  Timer? _renewalTimer;
  bool _held = false;

  Future<bool> acquire() async {
    if (_held) return true;

    final deadline = DateTime.now().add(_acquisitionTimeout);
    while (true) {
      final acquired = await _tryAcquire();
      if (acquired) {
        _held = true;
        _renewalTimer ??= Timer.periodic(
          _renewInterval,
          (_) => unawaited(_renew()),
        );
        return true;
      }

      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Verifies that this runtime still owns an unexpired lease.
  ///
  /// A runtime can be suspended long enough for another runtime to take over.
  /// The old runtime must never silently continue a new sync phase after that
  /// takeover. Callers should abort the current cycle and let a later trigger
  /// retry it.
  Future<void> ensureHeld() async {
    if (!_held) {
      throw const SyncExecutionLeaseLost();
    }
    final row = await (_db.select(_db.syncRuntimeLeases)
          ..where((item) => item.name.equals(leaseName))
          ..limit(1))
        .getSingleOrNull();
    final now = DateTime.now();
    if (row == null || row.ownerId != _ownerId || !row.expiresAt.isAfter(now)) {
      _held = false;
      _renewalTimer?.cancel();
      _renewalTimer = null;
      throw const SyncExecutionLeaseLost();
    }
  }

  /// Validates ownership while deliberately issuing a write statement.
  ///
  /// This method is intended to be the first database operation inside a
  /// canonical apply transaction. The UPDATE acquires SQLite's writer lock
  /// before eligibility checks or reconciliation can run, so an expired lease
  /// cannot be taken over in the gap between a transaction's initial read and
  /// its first business-data write.
  Future<T> runProtectedTransaction<T>(
    AppDatabase db,
    Future<T> Function() action,
  ) async {
    return db.transaction(() async {
      await ensureHeldForTransaction();
      return action();
    });
  }

  Future<void> ensureHeldForTransaction() async {
    if (!_held) {
      throw const SyncExecutionLeaseLost();
    }

    final now = DateTime.now();
    final updated = await (_db.update(_db.syncRuntimeLeases)
          ..where(
            (row) =>
                row.name.equals(leaseName) &
                row.ownerId.equals(_ownerId) &
                row.expiresAt.isBiggerThanValue(now),
          ))
        .write(
      SyncRuntimeLeasesCompanion.custom(
        expiresAt: _db.syncRuntimeLeases.expiresAt,
      ),
    );
    if (updated != 1) {
      _held = false;
      _renewalTimer?.cancel();
      _renewalTimer = null;
      throw const SyncExecutionLeaseLost();
    }
  }

  Future<void> release() async {
    _renewalTimer?.cancel();
    _renewalTimer = null;
    if (!_held) return;

    await (_db.delete(_db.syncRuntimeLeases)
          ..where(
            (row) =>
                row.name.equals(leaseName) &
                row.ownerId.equals(_ownerId),
          ))
        .go();
    _held = false;
  }

  Duration get _renewInterval {
    final millis = (_leaseDuration.inMilliseconds ~/ 3).clamp(1000, 30000);
    return Duration(milliseconds: millis);
  }

  Future<bool> _tryAcquire() async {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.syncRuntimeLeases)
            ..where((row) => row.name.equals(leaseName))
            ..limit(1))
          .getSingleOrNull();

      final now = DateTime.now();
      final canTakeOver = existing == null || !existing.expiresAt.isAfter(now);
      if (!canTakeOver && existing.ownerId != _ownerId) return false;

      final expiresAt = now.add(_leaseDuration);
      if (existing == null) {
        await _db.into(_db.syncRuntimeLeases).insert(
              SyncRuntimeLeasesCompanion.insert(
                name: leaseName,
                ownerId: _ownerId,
                acquiredAt: now,
                expiresAt: expiresAt,
              ),
            );
      } else {
        await (_db.update(_db.syncRuntimeLeases)
              ..where((row) => row.name.equals(leaseName)))
            .write(
          SyncRuntimeLeasesCompanion(
            ownerId: Value(_ownerId),
            acquiredAt: Value(existing.ownerId == _ownerId
                ? existing.acquiredAt
                : now),
            expiresAt: Value(expiresAt),
          ),
        );
      }
      return true;
    });
  }

  Future<void> _renew() async {
    if (!_held) return;
    final updated = await (_db.update(_db.syncRuntimeLeases)
          ..where(
            (row) =>
                row.name.equals(leaseName) &
                row.ownerId.equals(_ownerId),
          ))
        .write(
      SyncRuntimeLeasesCompanion(
        expiresAt: Value(DateTime.now().add(_leaseDuration)),
      ),
    );
    if (updated != 1) {
      _held = false;
      _renewalTimer?.cancel();
      _renewalTimer = null;
    }
  }
}


class SyncExecutionLeaseLost implements Exception {
  const SyncExecutionLeaseLost();

  @override
  String toString() => 'Cloud Sync execution lease was lost to another runtime.';
}
