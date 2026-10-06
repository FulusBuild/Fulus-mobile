import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

const _dbPath = String.fromEnvironment('FULUS_SYNC_PROBE_DB_PATH');
const _mode = String.fromEnvironment('FULUS_SYNC_PROBE_MODE');

void main() {
  test('cross-process sync lease probe', () async {
    if (_dbPath.isEmpty || _mode.isEmpty) {
      fail('FULUS_SYNC_PROBE_DB_PATH and FULUS_SYNC_PROBE_MODE are required');
    }
    if (_mode != 'blocked' && _mode != 'acquire') {
      fail('FULUS_SYNC_PROBE_MODE must be blocked or acquire');
    }

    final db = AppDatabase.forTesting(
      NativeDatabase(
        File(_dbPath),
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
        _mode == 'acquire',
        reason: 'mode=$_mode acquired=$acquired',
      );
    } finally {
      await lease.release();
      await db.close();
    }
  });
}
