/// A restore has to replace the live SQLite file on disk while the app
/// holds an open connection to it — writing under an open connection's
/// feet (especially with WAL mode, which keeps extra -wal/-shm files
/// alongside the main one) risks corruption. This is the seam
/// BackupRepositoryImpl needs to do that safely: close the app's one
/// Drift connection, replace the file, then get the app back onto a
/// fresh connection to the replaced file — without BackupRepositoryImpl
/// needing to know what `AppDatabase` actually looks like today.
///
/// The native implementation is `AppDatabaseLifecycle`, wired during app
/// bootstrap. Reopening creates a fresh Drift connection and updates the
/// database handle used by newly resolved dependencies. Existing repositories
/// can still retain the closed instance, so the UI requires an app restart
/// after a successful restore.
abstract class DatabaseLifecycle {
  /// Absolute path to the live SQLite file.
  Future<String> currentDatabasePath();

  /// Closes the app's Drift connection so the file is safe to
  /// overwrite. Must be called, and awaited, before touching the file.
  Future<void> closeForMaintenance();

  /// Re-opens a Drift connection to whatever is now at
  /// [currentDatabasePath] and makes it the one the rest of the app
  /// uses. Must be called after the file swap, even if the swap failed,
  /// so the app is never left with no working database connection.
  Future<void> reopenAfterMaintenance();
}
