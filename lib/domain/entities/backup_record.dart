/// Backups — Stage 10.
///
/// Deliberately file-based, not a database table: backup_service.py's
/// own design lists backups by globbing the backup directory and
/// reading file stat() metadata (filename, size, mtime) rather than
/// keeping a separate database record of what's been backed up — a
/// backup row in the same SQLite file it's meant to protect would be
/// exactly the kind of thing a restore could silently make inconsistent
/// with reality (e.g. a restored-from-backup database "remembering" a
/// list of backups that predates it, or missing ones taken after the
/// snapshot it was restored from). Mirroring the file-is-the-record
/// approach keeps the backup list always truthful: what's actually in
/// the backup folder, nothing more, nothing cached.
class BackupMetadata {
  const BackupMetadata({
    required this.fileName,
    required this.label,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String fileName;

  /// manual | scheduled | pre_restore_safety — mirrors
  /// backup_service.create_backup's `label` parameter and its three
  /// call sites exactly.
  final String label;
  final DateTime createdAt;
  final int sizeBytes;
}

class BackupResult {
  const BackupResult({required this.metadata});
  final BackupMetadata metadata;
}

class RestoreResult {
  const RestoreResult({
    required this.restoredFrom,
    required this.restoredAt,

    /// The filename of the automatic pre-restore safety snapshot, or
    /// null when there was no live database to protect (a fresh
    /// install) — mirrors restore_backup's own `safety_snapshot`
    /// null-when-nothing-to-protect case exactly.
    this.safetySnapshotFileName,
  });

  final String restoredFrom;
  final DateTime restoredAt;
  final String? safetySnapshotFileName;
}
