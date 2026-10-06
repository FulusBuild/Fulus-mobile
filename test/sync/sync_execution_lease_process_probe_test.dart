import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

void main() {
  test('cross-process sync lease probe', () async {
    final path = Platform.environment['FULUS_SYNC_PROBE_DB_PATH'];
    final mode = Platform.environment['FULUS_SYNC_PROBE_MODE'];
    if (path == null || mode == null) {
      fail('FULUS_SYNC_PROBE_DB_PATH and FULUS_SYNC_PROBE_MODE are required');
    }
    if (mode != 'blocked' && mode != 'acquire') {
      fail('FULUS_SYNC_PROBE_MODE must be blocked or acquire');
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
      expect(
        acquired,
        mode == 'acquire',
        reason: 'mode=$mode acquired=$acquired',
      );
    } finally {
      await lease.release();
      await db.close();
    }
  });
}
