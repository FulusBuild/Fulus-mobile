import 'dart:io';

import 'package:drift/native.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/sync_execution_lease_process_probe.dart '
      '<db-path> <blocked|acquire>',
    );
    exitCode = 64;
    return;
  }

  final path = args[0];
  final mode = args[1];
  if (mode != 'blocked' && mode != 'acquire') {
    stderr.writeln('mode must be blocked or acquire');
    exitCode = 64;
    return;
  }

  final db = AppDatabase.forTesting(
    NativeDatabase(
      File(path),
      setup: (database) {
        database.execute('PRAGMA journal_mode=WAL');
        database.execute('PRAGMA busy_timeout=1000');
      },
    ),
  );
  final lease = SyncExecutionLease(
    db,
    acquisitionTimeout: const Duration(milliseconds: 750),
  );

  try {
    final acquired = await lease.acquire();
    final expected = mode == 'blocked' ? !acquired : acquired;
    if (!expected) {
      stderr.writeln('unexpected lease result: mode=$mode acquired=$acquired');
      exitCode = 1;
    } else {
      stdout.writeln('PASS: mode=$mode acquired=$acquired');
      exitCode = 0;
    }
  } finally {
    await lease.release();
    await db.close();
  }
}
