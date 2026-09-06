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
  /// at a time. Also mirrors that snapshot into the public Downloads
  /// folder, best-effort — see [exportToDownloads]'s own doc comment
  /// for why a second copy outside this app's own folder, written
  /// automatically rather than requiring the person to pick a location
  /// first, is what actually makes an automatic backup survive a
  /// reinstall, not this method's local half on its own. Cheap and safe
  /// to call often: [createBackup]'s VACUUM INTO never blocks the live
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

  /// Copies [sourceFileName] (a name already in [listBackups]) into the
  /// device's public Downloads folder, under a "Fulus" subfolder, as a
  /// single fixed-name file that each call overwrites — the "single
  /// file that keeps itself current" promise every other automatic
  /// backup in this app makes, not one more timestamped file piling up
  /// where the person would have to clean it out themselves.
  ///
  /// This — not [backupDirectoryPath] — is what actually survives an
  /// uninstall: Android deletes an app's own folders, internal AND
  /// external alike, the moment the app itself is uninstalled, by
  /// design, with no exception this app's own permissions can opt out
  /// of (see that getter's own doc comment). Downloads is public,
  /// shared storage — nothing about removing Fulus touches it.
  ///
  /// Implemented natively (MainActivity.kt, `fulus/backup_export`
  /// channel): on Android 10+ (scoped storage) writing an app's own new
  /// file into the public Downloads collection needs the MediaStore
  /// API, not a plain file path — no `dart:io` call from this side can
  /// do it. No picker, no permission prompt on Android 10+: creating a
  /// new file of the app's own is allowed by default. Android 8–9
  /// (below scoped storage) fall back to a direct file write gated on
  /// `WRITE_EXTERNAL_STORAGE` (manifest-declared `maxSdkVersion="28"`,
  /// since scoped storage makes it irrelevant above that). Best-effort
  /// either way — see [runAutoBackup]'s own try/catch around this call
  /// for what happens if it fails.
  Future<void> exportToDownloads(String sourceFileName);

  /// Best starting point for the "pick a backup file" picker —
  /// prioritized by how likely it is to actually have something in it,
  /// not just [backupDirectoryPath] unconditionally. That folder is
  /// exactly what's empty right when this matters most: immediately
  /// after a reinstall (see [exportToDownloads]'s own doc comment on
  /// why). Falls back to [backupDirectoryPath] only if it genuinely has
  /// something in it, and to a guess at the public Downloads/Fulus
  /// folder [exportToDownloads] itself writes to as a last resort —
  /// the one place, of these three, actually designed to still be
  /// there after a reinstall.
  Future<String> initialRestoreDirectory();

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
