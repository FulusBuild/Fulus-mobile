import '../entities/backup_record.dart';

/// Stage 10. Mirrors backend/app/services/backup_service.py's four
/// operations exactly (create, list, restore, delete), plus the prune
/// rule for scheduled backups — see backup_engine.dart for the pure
/// logic (filename generation, prune selection, path-traversal guard)
/// that this repository's implementation delegates to before touching
/// the filesystem.
abstract class BackupRepository {
  /// Creates a timestamped snapshot of the live database. [label] is
  /// one of 'manual' | 'scheduled' | 'pre_restore_safety' — mirrors
  /// create_backup's own vocabulary. Safe to call while the app is in
  /// normal use: performs a WAL checkpoint first so the copied file is
  /// never mid-write (see backup_repository_impl.dart's doc comment for
  /// why this is done via checkpoint+copy rather than any online-backup
  /// API).
  Future<BackupResult> createBackup({String label = 'manual'});

  /// Lists backups newest-first, scanning the backup directory itself —
  /// there is no cached/DB-backed list; see backup_record.dart's class
  /// doc for why.
  Future<List<BackupMetadata>> listBackups();

  /// Replaces the live database with [fileName]'s contents. Always
  /// takes an automatic 'pre_restore_safety' snapshot of the CURRENT
  /// database first (mirrors restore_backup exactly), so a restore can
  /// itself be undone by restoring that safety snapshot.
  Future<RestoreResult> restoreBackup(String fileName);

  /// Deletes one backup file. Rejects (throws
  /// InvalidBackupFileName from module_failures.dart) any [fileName]
  /// that isn't a bare filename already present in [listBackups] —
  /// mirrors backend delete_backup's path-traversal guard (no '/', no
  /// '..', must match the backup naming pattern) so a malformed or
  /// tampered filename can never be used to delete or read outside the
  /// backup directory.
  Future<void> deleteBackup(String fileName);

  /// Copies [fileName] into a location the Android Share Sheet can read
  /// (via share_plus) and returns that path — the mechanism Volume 11 /
  /// the Implementation Bible call for ("Export uses Android Share
  /// Sheet. No server.").
  Future<String> prepareForShare(String fileName);

  /// Runs create + prune in one call — the entry point for a background
  /// scheduled-backup task (WorkManager/native alarm, wired up outside
  /// this module). Keeps at most [keep] scheduled-label backups,
  /// oldest deleted first; manual and pre_restore_safety backups are
  /// never touched by pruning — mirrors backup_service's own
  /// prune-only-scheduled behavior exactly.
  Future<BackupResult> runScheduledBackup({int keep = 14});
}
