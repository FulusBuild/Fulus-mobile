import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

void main() {
  final configFile = File('.dart_tool/fulus_sync_probe_config');
  final configured = configFile.existsSync();

  test(
    'cross-process sync lease probe',
    () async {
      final config = await configFile.readAsLines();
      if (config.length < 2) {
        fail('sync probe config is incomplete');
      }
      final dbPath = config[0];
      final mode = config[1];
      if (dbPath.isEmpty || mode.isEmpty) {
        fail('sync probe config contains an empty value');
      }
      if (mode != 'blocked' && mode != 'acquire') {
        fail('FULUS_SYNC_PROBE_MODE must be blocked or acquire');
      }

      final db = AppDatabase.forTesting(
        NativeDatabase(
          File(dbPath),
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
    },
    skip: configured
        ? null
        : 'Probe is only executed by the cross-process parent test.',
  );
}
