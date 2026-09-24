import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> resolveDatabaseFilePath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return p.join(dbFolder.path, 'fulus_mobile.sqlite');
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
