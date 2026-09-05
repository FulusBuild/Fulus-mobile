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

  /// Runs create + prune-to-one in one call — the activity-triggered
  /// counterpart to [runScheduledBackup]. Labels the new snapshot
  /// 'auto' and immediately deletes every OTHER 'auto'-labeled file
  /// (`BackupEngine.selectPruneCandidates(..., label: 'auto', keep: 1)`),
  /// so exactly one automatic backup ever exists in [backupDirectoryPath]
  /// at a time. Also mirrors that snapshot into [durableBackupFolder],
  /// best-effort, if one has been set — see that method's own doc
  /// comment for why a second copy outside this app's own folder is
  /// what actually makes an automatic backup survive a reinstall, not
  /// this method's local half on its own. Cheap and safe to call
  /// often: [createBackup]'s VACUUM INTO never blocks the live
  /// database (see this repository's own implementation doc comment),
  /// so the caller (an app-wide listener on whatever signals real user
  /// activity) can call this after every burst of activity with
  /// nothing more than an ordinary debounce.
  Future<BackupResult> runAutoBackup();

  /// The folder every backup in [listBackups] actually lives in, as a
  /// real, absolute filesystem path — for display (so "where did my
  /// backup go" has a literal on-screen answer) and so a file-picker
  /// call can be pointed at it as a starting point. Creates the
  /// directory if it doesn't exist yet, same as every other method
  /// here that touches it.
  Future<String> backupDirectoryPath();

  /// The durable, user-picked folder outside this app's own sandbox
  /// that [runAutoBackup] mirrors its latest snapshot into, if one has
  /// been set — see [setDurableBackupFolder]'s own doc comment for why
  /// this exists at all. Null until the person has picked one.
  Future<String?> durableBackupFolder();

  /// Remembers [path] — a real folder the person picked via Android's
  /// own document-tree picker — as the mirror target every future
  /// [runAutoBackup] copies its latest snapshot into, so a backup
  /// taken today is still sitting there, outside this app's own
  /// sandbox, even after an uninstall/reinstall. That's the one thing
  /// nothing under [backupDirectoryPath] can ever promise: Android
  /// deletes an app's own folders — internal AND external, whichever
  /// this app is using — the moment the app itself is uninstalled, by
  /// design, with no exception this app can opt out of. Persisted
  /// locally (SharedPreferences), same as every other simple
  /// device-local setting in this app (AppLockConfig, SyncConfig).
  Future<void> setDurableBackupFolder(String path);

  /// Backup & Restore (schemaVersion 10): brings a file the user picked
  /// from anywhere on their device — a different app's export folder,
  /// an SD card, a cloud-sync app's local copy, a file received over
  /// email or chat — into this app's own managed backups, so it can go
  /// through the exact same [restoreBackup] every other backup does.
  /// This is the "pick a backup file from storage" half of Backup &
  /// Restore's own task requirement; [listBackups] finding something
  /// automatically in this app's own folder is the other half.
  ///
  /// [sourcePath] is a real filesystem path to the picked file (what a
  /// file-picker plugin returns for a local file) — this repository
  /// doesn't do the picking itself, same division of responsibility
  /// [AuthRepository] and every presentation-layer caller already keep
  /// elsewhere in this app. Validates the file actually looks like a
  /// SQLite database (checks for SQLite's own 16-byte header magic)
  /// before copying it in — rejects anything else with
  /// [InvalidBackupFileName] rather than silently accepting a file
  /// that would only fail confusingly later, inside [restoreBackup]
  /// itself. The copy is stored under a freshly generated compliant
  /// name (label 'imported') — [sourcePath]'s own filename is never
  /// reused, since a file from outside this app has no reason to
  /// already match [validateFileName]'s naming pattern.
  Future<BackupResult> importBackupFile(String sourcePath);
}
