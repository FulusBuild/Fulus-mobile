import '../../domain/entities/backup_record.dart';
import '../../domain/repositories/backup_repository.dart';
import '../../domain/repositories/database_lifecycle.dart';
import '../../domain/usecases/backup_engine.dart';

/// Backup is a native/mobile filesystem feature. Web uses Drift/WASM and
/// deliberately does not expose native SQLite-file backup operations.
class BackupRepositoryImpl implements BackupRepository {
  BackupRepositoryImpl({
    required DatabaseLifecycle lifecycle,
    BackupEngine engine = const BackupEngine(),
  });

  Never _unsupported() => throw UnsupportedError(
        'File-based Fulus backups are only available on native platforms.',
      );

  @override
  Future<BackupResult> createBackup({String label = 'manual'}) async => _unsupported();

  @override
  Future<List<BackupMetadata>> listBackups() async => _unsupported();

  @override
  Future<RestoreResult> restoreBackup(String fileName) async => _unsupported();

  @override
  Future<void> deleteBackup(String fileName) async => _unsupported();

  @override
  Future<String> prepareForShare(String fileName) async => _unsupported();

  @override
  Future<BackupResult> runScheduledBackup({int keep = 14}) async => _unsupported();

  @override
  Future<BackupResult> runAutoBackup() async => _unsupported();

  @override
  Future<String> backupDirectoryPath() async => _unsupported();

  @override
  Future<void> exportToDownloads(String sourceFileName) async => _unsupported();

  @override
  Future<String?> findDurableBackup() async => _unsupported();

  @override
  Future<String> initialRestoreDirectory() async => _unsupported();

  @override
  Future<BackupResult> importBackupFile(String sourcePath) async => _unsupported();
}
