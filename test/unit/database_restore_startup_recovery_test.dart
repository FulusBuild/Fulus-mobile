import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database_connection_native.dart';

void main() {
  late Directory directory;
  late String databasePath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'fulus-restore-recovery-',
    );
    databasePath =
        '${directory.path}${Platform.pathSeparator}fulus_mobile.sqlite';
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'recovers the newest previous database when restore left no live file',
    () async {
      final older = File('$databasePath.restore-100.previous');
      final newer = File('$databasePath.restore-200.previous');
      await older.writeAsString('older database');
      await newer.writeAsString('newer database');

      await recoverDatabaseAfterInterruptedRestore(databasePath);

      expect(await File(databasePath).readAsString(), 'newer database');
      expect(await older.exists(), isTrue);
      expect(await newer.exists(), isFalse);
    },
  );

  test(
    'does not replace an installed live database with an older previous file',
    () async {
      final live = File(databasePath);
      final previous = File('$databasePath.restore-200.previous');
      await live.writeAsString('installed restore');
      await previous.writeAsString('old database');

      await recoverDatabaseAfterInterruptedRestore(databasePath);

      expect(await live.readAsString(), 'installed restore');
      expect(await previous.exists(), isTrue);
    },
  );

  test('ignores temporary files and malformed restore names', () async {
    final staged = File('$databasePath.restore-300.tmp');
    final malformed = File('$databasePath.restore-abc.previous');
    await staged.writeAsString('staged file');
    await malformed.writeAsString('unrecognized file');

    await recoverDatabaseAfterInterruptedRestore(databasePath);

    expect(await File(databasePath).exists(), isFalse);
    expect(await staged.exists(), isTrue);
    expect(await malformed.exists(), isTrue);
  });
}
