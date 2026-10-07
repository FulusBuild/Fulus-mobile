import '../../../domain/repositories/database_lifecycle.dart';
import '../../../sync/sync_execution_lease.dart';
import 'database.dart';

/// The concrete `AppDatabase`-backed `DatabaseLifecycle` INTEGRATION.md
/// asked for — used only by `BackupRepositoryImpl` (Stage 10) to close
/// the live connection before a restore overwrites the file, then get a
/// working connection back afterward.
///
/// IMPORTANT, found while actually wiring this rather than templating
/// it: [reopenAfterMaintenance] can only give the app *a* fresh,
/// working `AppDatabase` — it cannot make every repository already
/// holding a direct reference to the OLD instance (SaleRepositoryImpl,
/// CustomerRepositoryImpl, every other repository bootstrap.dart
/// constructed with `database` passed directly in) start using the new
/// one instead. Those references were captured at construction time,
/// not looked up reactively, so nothing short of reconstructing the
/// entire DI graph — every repository, every sync handler, the whole
/// of bootstrap.dart's return value — actually achieves a true
/// mid-session hot-swap. That's a real, separate piece of work (making
/// `AppDatabase` itself swappable behind a stable indirection everything
/// depends on instead of a direct reference), not something this class
/// can paper over by itself.
///
/// So: this class does the part that's genuinely safe and correct on
/// its own (close the connection so the file can be overwritten without
/// risking corruption; open a new, working connection to whatever is
/// there afterward, so the app is never left with zero working
/// connection) and is honest about the rest. The correct, honest UX for
/// BackupRepositoryImpl.restore's caller (a future Settings screen) is
/// to prompt the user to restart the app once restore succeeds — the
/// same pattern most apps use for exactly this class of operation — not
/// to claim the restored data is live everywhere without one.
/// [onReopened] exists so bootstrap.dart can update whatever it wants
/// with the fresh instance (e.g. the value backing databaseProvider,
/// for anything constructed AFTER a restart that reads it fresh) without
/// this class needing to know about ProviderContainer or Riverpod at
/// all.
class AppDatabaseLifecycle implements DatabaseLifecycle {
  AppDatabaseLifecycle({
    required AppDatabase Function() getDatabase,
    required void Function(AppDatabase) onReopened,
    void Function()? onMaintenanceClosed,
  })  : _getDatabase = getDatabase,
        _onReopened = onReopened,
        _onMaintenanceClosed = onMaintenanceClosed;

  final AppDatabase Function() _getDatabase;
  final void Function(AppDatabase) _onReopened;
  final void Function()? _onMaintenanceClosed;
  SyncExecutionLease? _maintenanceLease;

  @override
  Future<String> currentDatabasePath() => AppDatabase.resolveDatabasePath();

  @override
  Future<void> closeForMaintenance() async {
    if (_maintenanceLease != null) {
      throw StateError('Database maintenance is already in progress.');
    }
    final database = _getDatabase();
    final lease = SyncExecutionLease(database);
    final acquired = await lease.acquireMaintenance();
    if (!acquired) {
      throw StateError('Fulus Cloud sync is still active. Please try the restore again.');
    }
    _maintenanceLease = lease;
    try {
      // The SQLite lease row cannot be renewed after this connection closes.
      // Keep the physical sidecar FileLock held instead while the database
      // pathname is replaced.
      lease.suspendMaintenanceRenewalForDatabaseReplacement();
      await database.close();
      // Closing the live database is the irreversible DI boundary: existing
      // repositories still reference the closed instance until process
      // restart. Latch the restart requirement before any restore file
      // replacement or reopen attempt can fail, so rollback/failure paths
      // cannot return the UI to normal business use accidentally.
      _onMaintenanceClosed?.call();
    } catch (_) {
      await lease.releaseMaintenance();
      _maintenanceLease = null;
      rethrow;
    }
  }

  @override
  Future<void> reopenAfterMaintenance() async {
    // A fresh instance, not the closed one — a closed Drift database
    // can't be reused. See this class's own doc comment for why this
    // being "the app's working database again" is not the same claim as
    // "every existing repository now uses it."
    final fresh = AppDatabase.open();
    try {
      _onReopened(fresh);
    } catch (_) {
      // The callback updates the application's database handle. If that
      // handoff fails, do not leak the freshly opened connection while the
      // maintenance fence remains held; the restore caller must be able to
      // roll the file back and retry the reopen safely.
      await fresh.close();
      rethrow;
    }

    final lease = _maintenanceLease;
    _maintenanceLease = null;
    if (lease != null) {
      await lease.releaseMaintenanceOn(fresh);
    }
  }
}
