import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../core/errors/module_failures.dart';
import '../../domain/entities/backup_record.dart';
import '../../domain/repositories/backup_repository.dart';
import '../../domain/repositories/database_lifecycle.dart';
import '../../domain/usecases/backup_engine.dart';

/// Backend's own backup_service.py uses Python's `sqlite3.backup()` (the
/// SQLite C online backup API) specifically because it "so backups are
/// consistent even while the database is actively used." This
/// implementation reaches the same guarantee a different way: SQLite's
/// `VACUUM INTO` statement, run over a fresh, separate connection to the
/// live database file. Per SQLite's own documentation, VACUUM INTO does
/// NOT require exclusive access to the source database — concurrent
/// readers/writers on the live app connection are unaffected — it only
/// needs exclusive access to the new (backup) file being created, which
/// is guaranteed here simply by writing to a fresh timestamped filename
/// every time. This avoids needing the C backup API's step/finish loop
/// bound into Dart (package:sqlite3 doesn't expose one), while giving
/// an equally atomic, equally consistent snapshot — and, as a bonus
/// over a raw file copy, VACUUM INTO also compacts the destination file.
class BackupRepositoryImpl implements BackupRepository {
  BackupRepositoryImpl({
    required DatabaseLifecycle lifecycle,
    BackupEngine engine = const BackupEngine(),
  })  : _lifecycle = lifecycle,
        _engine = engine;

  final DatabaseLifecycle _lifecycle;
  final BackupEngine _engine;

  /// Backup & Restore discoverability fix: this used to resolve under
  /// [getApplicationDocumentsDirectory], which on Android is this
  /// app's fully private internal storage — invisible to any file
  /// manager and unreachable by Android's own document picker (the
  /// exact mechanism [FilePicker.pickFiles] uses from the Backup &
  /// Restore screen), which is exactly why "where did my backup go"
  /// had no real answer before this. [getExternalStorageDirectory] is
  /// still this app's own sandboxed folder — no runtime storage
  /// permission needed on any Android version this app targets, since
  /// it's the app-specific external directory, not shared storage —
  /// but it lives on the shared /storage/emulated/0 volume a file
  /// manager can actually browse to, and is what [backupDirectoryPath]
  /// now surfaces on that screen so the location is never a mystery.
  /// Falls back to the private documents directory only if external
  /// storage is genuinely unavailable (no shared volume / a platform
  /// other than Android) — still fully functional, just not as easy
  /// to find, matching this getter's old behavior on every platform.
  Future<Directory> _backupDir() async {
    final external = await getExternalStorageDirectory();
    final root = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> backupDirectoryPath() async => (await _backupDir()).path;

  static const _durableFolderKey = 'fulus_backup_durable_folder';

  @override
  Future<String?> durableBackupFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_durableFolderKey);
  }

  @override
  Future<void> setDurableBackupFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_durableFolderKey, path);
  }

  @override
  Future<BackupResult> createBackup({String label = 'manual'}) async {
    final dbPath = await _lifecycle.currentDatabasePath();
    if (!await File(dbPath).exists()) {
      throw const BackupException('Database file not found. Nothing to back up.');
    }

    final now = DateTime.now().toUtc();
    final fileName = _engine.buildFileName(label: label, createdAtUtc: now);
    final destPath = p.join((await _backupDir()).path, fileName);

    final src = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    try {
      src.execute('VACUUM INTO ?', [destPath]);
    } finally {
      src.close();
    }

    final size = await File(destPath).length();
    final metadata = BackupMetadata(fileName: fileName, label: label, createdAt: now, sizeBytes: size);
    return BackupResult(metadata: metadata);
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final dir = await _backupDir();
    if (!await dir.exists()) return const [];
    // BUG FIX (integration pass): was startsWith('bms_') only — see
    // backup_engine.dart's buildFileName doc comment for why this
    // module used the pre-rename prefix throughout. Matches both the
    // current prefix and the legacy one, same as the backend's own
    // list_backups does.
    final entries = await dir
        .list()
        .where((e) =>
            e is File &&
            (p.basename(e.path).startsWith('fulus_') ||
                p.basename(e.path).startsWith('bms_')))
        .toList();
    final backups = <BackupMetadata>[];
    for (final entry in entries) {
      final file = entry as File;
      final stat = await file.stat();
      final name = p.basename(file.path);
      backups.add(BackupMetadata(
        fileName: name,
        label: _labelFromFileName(name),
        createdAt: stat.modified.toUtc(),
        sizeBytes: stat.size,
      ));
    }
    return _engine.sortNewestFirst(backups);
  }

  /// Best-effort label recovery for display purposes only (e.g. showing
  /// "scheduled" in a backups list) — never relied on for the actual
  /// prune rule, which filters by this same prefix match directly in
  /// [runScheduledBackup], not by round-tripping through this parse.
  String _labelFromFileName(String fileName) {
    for (final label in const ['pre_restore_safety', 'scheduled', 'imported', 'auto', 'manual']) {
      if (fileName.startsWith('fulus_${label}_') || fileName.startsWith('bms_${label}_')) {
        return label;
      }
    }
    return 'manual';
  }

  @override
  Future<RestoreResult> restoreBackup(String fileName) async {
    _engine.validateFileName(fileName);
    final backupPath = p.join((await _backupDir()).path, fileName);
    if (!await File(backupPath).exists()) {
      throw BackupException('Backup "$fileName" not found.');
    }

    final dbPath = await _lifecycle.currentDatabasePath();

    String? safetyFileName;
    if (await File(dbPath).exists()) {
      final safety = await createBackup(label: 'pre_restore_safety');
      safetyFileName = safety.metadata.fileName;
    }

    await _lifecycle.closeForMaintenance();
    try {
      await File(backupPath).copy(dbPath);
      // A stale -wal/-shm from the connection that was just closed
      // could otherwise be replayed against the just-restored main
      // file, applying writes that predate the backup and silently
      // defeating the whole point of restoring it.
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
    } finally {
      // Always reopen, even if the copy above failed, so the app is
      // never left with no working database connection at all.
      await _lifecycle.reopenAfterMaintenance();
    }

    return RestoreResult(
      restoredFrom: fileName,
      restoredAt: DateTime.now().toUtc(),
      safetySnapshotFileName: safetyFileName,
    );
  }

  @override
  Future<void> deleteBackup(String fileName) async {
    _engine.validateFileName(fileName);
    final path = p.join((await _backupDir()).path, fileName);
    final file = File(path);
    if (!await file.exists()) {
      throw BackupException('Backup "$fileName" not found.');
    }
    await file.delete();
  }

  @override
  Future<String> prepareForShare(String fileName) async {
    _engine.validateFileName(fileName);
    final path = p.join((await _backupDir()).path, fileName);
    if (!await File(path).exists()) {
      throw BackupException('Backup "$fileName" not found.');
    }
    // Already in a location share_plus's Share.shareXFiles can read
    // directly (it handles the Android FileProvider wiring itself) —
    // no separate copy needed, unlike a temp-cache receipt file that
    // gets regenerated from a Sale on every share.
    return path;
  }

  @override
  Future<BackupResult> runScheduledBackup({int keep = 14}) async {
    final result = await createBackup(label: 'scheduled');
    final all = await listBackups();
    final toDelete = _engine.selectPruneCandidates(all, keep: keep);
    for (final backup in toDelete) {
      await deleteBackup(backup.fileName);
    }
    return result;
  }

  @override
  Future<BackupResult> runAutoBackup() async {
    final result = await createBackup(label: 'auto');
    final all = await listBackups();
    final toDelete = _engine.selectPruneCandidates(all, label: 'auto', keep: 1);
    for (final backup in toDelete) {
      await deleteBackup(backup.fileName);
    }
    await _mirrorToDurableFolder(result.metadata.fileName);
    return result;
  }

  /// Best-effort, deliberately silent — the durable folder is a real
  /// directory the person granted access to at some point in the
  /// past, and Android can invalidate that grant behind the app's
  /// back (folder moved or deleted, SD card removed, permissions
  /// reset). None of that should ever affect the actual local backup
  /// [runAutoBackup] just made, which is why this is a separate step
  /// after that backup is already safely on disk, not something
  /// [createBackup] itself does. One stable filename, not one per
  /// timestamp, for the same reason the local 'auto' backup is kept
  /// to exactly one file: a single copy that keeps itself current,
  /// not an ever-growing pile the person has to clean up by hand.
  Future<void> _mirrorToDurableFolder(String fileName) async {
    try {
      final folder = await durableBackupFolder();
      if (folder == null) return;
      final source = File(p.join((await _backupDir()).path, fileName));
      if (!await source.exists()) return;
      await source.copy(p.join(folder, 'fulus_backup_latest.db'));
    } catch (_) {
      // Silent — see doc comment above.
    }
  }

  @override
  Future<BackupResult> importBackupFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const BackupException('Selected file could not be found.');
    }

    // SQLite's own on-disk format starts every valid database file with
    // this exact 16-byte magic header (the C library's own documented
    // guarantee, not something specific to this app) — checked before
    // ever touching the live database, so a wrong file (a stray photo,
    // a renamed .txt, someone else's export in a different format) is
    // rejected right here with a clear reason instead of failing deep
    // inside restoreBackup with a raw SQLite error.
    const header = 'SQLite format 3\u0000';
    final raf = await source.open();
    List<int> bytes;
    try {
      bytes = await raf.read(header.length);
    } finally {
      await raf.close();
    }
    final looksLikeSqlite = bytes.length == header.length && String.fromCharCodes(bytes) == header;
    if (!looksLikeSqlite) {
      throw const BackupException(
        "That file doesn't look like a Fulus backup.",
      );
    }

    final now = DateTime.now().toUtc();
    final fileName = _engine.buildFileName(label: 'imported', createdAtUtc: now);
    final destPath = p.join((await _backupDir()).path, fileName);
    await source.copy(destPath);

    final size = await File(destPath).length();
    final metadata = BackupMetadata(fileName: fileName, label: 'imported', createdAt: now, sizeBytes: size);
    return BackupResult(metadata: metadata);
  }
}
