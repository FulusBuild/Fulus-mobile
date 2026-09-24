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
      if (!canTakeOver && existing!.ownerId != _ownerId) return false;

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
