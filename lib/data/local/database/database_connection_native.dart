import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> resolveDatabaseFilePath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final path = p.join(dbFolder.path, 'fulus_mobile.sqlite');
  await recoverDatabaseAfterInterruptedRestore(path);
  return path;
}

/// Restore moves the previous live file aside before installing the staged
/// backup. If Android kills the process in that narrow interval, the live path
/// is absent on next launch. Recover the newest preserved live database before
/// Drift opens the path (which would otherwise create a blank database).
///
/// Only recover when the live path is absent. If it exists, it may be the
/// successfully installed restore and must not be replaced by the older file.
Future<void> recoverDatabaseAfterInterruptedRestore(String databasePath) async {
  final live = File(databasePath);
  if (await live.exists()) return;

  final directory = Directory(p.dirname(databasePath));
  if (!await directory.exists()) return;
  final prefix = '${p.basename(databasePath)}.restore-';
  final candidates = <({int stamp, File file})>[];
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.startsWith(prefix) || !name.endsWith('.previous')) continue;
    final stampText = name.substring(
      prefix.length,
      name.length - '.previous'.length,
    );
    final stamp = int.tryParse(stampText);
    if (stamp != null) candidates.add((stamp: stamp, file: entity));
  }
  if (candidates.isEmpty) return;
  candidates.sort((a, b) => b.stamp.compareTo(a.stamp));
  try {
    await candidates.first.file.rename(databasePath);
  } on FileSystemException {
    // Foreground startup and WorkManager can race to reopen the same file.
    // The first runtime may already have completed recovery while the second
    // was listing candidates; accept that only if the live path now exists.
    if (!await live.exists()) rethrow;
  }
}

LazyDatabase openDatabaseConnection() {
  return LazyDatabase(() async {
    final path = await resolveDatabaseFilePath();
    final file = File(path);

    if (!await file.exists()) {
      final legacyFile = File(p.join(file.parent.path, 'bms_mobile.sqlite'));
      if (await legacyFile.exists()) {
        await legacyFile.rename(file.path);
      }
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA journal_mode=WAL');
        // Canonical pull reconciliation briefly holds a SQLite write
        // transaction. A second runtime (for example, a foreground app
        // runtime while WorkManager is syncing) must wait for that transaction
        // rather than failing immediately with SQLITE_BUSY.
        database.execute('PRAGMA busy_timeout=5000');
      },
    );
  });
}
