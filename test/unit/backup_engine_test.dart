import 'package:fulus_mobile/core/errors/module_failures.dart';
import 'package:fulus_mobile/domain/entities/backup_record.dart';
import 'package:fulus_mobile/domain/usecases/backup_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = BackupEngine();

  group('buildFileName', () {
    // BUG FIX (integration pass): this generated 'bms_...' before —
    // see backup_engine.dart's own doc comment on buildFileName for why
    // (written against a pre-rename copy of the backend's
    // backup_service.py). Updated to match the actual current backend
    // convention.
    test('matches the fulus_{label}_{yyyyMMdd_HHmmss}.db pattern', () {
      final name = engine.buildFileName(label: 'manual', createdAtUtc: DateTime.utc(2026, 7, 30, 9, 5, 3));
      expect(name, 'fulus_manual_20260730_090503.db');
    });

    test('rejects an unknown label', () {
      expect(
        () => engine.buildFileName(label: 'bogus', createdAtUtc: DateTime.utc(2026, 1, 1)),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('validateFileName', () {
    test('accepts a well-formed generated filename', () {
      expect(() => engine.validateFileName('fulus_manual_20260730_090503.db'), returnsNormally);
    });

    test(
        'also accepts the legacy bms_ prefix — this device is new and has no '
        'real pre-rename backups, but the backend\'s own equivalent check '
        'accepts both, and keeping this one in sync with that is the point, '
        'not a guess at real legacy data existing here', () {
      expect(() => engine.validateFileName('bms_manual_20260730_090503.db'), returnsNormally);
    });

    test('rejects a path with a directory separator', () {
      expect(
        () => engine.validateFileName('../etc/fulus_manual_20260730_090503.db'),
        throwsA(isA<InvalidBackupFileName>()),
      );
    });

    test('rejects a name containing ".."', () {
      expect(
        () => engine.validateFileName('fulus_ma..nual_20260730_090503.db'),
        throwsA(isA<InvalidBackupFileName>()),
      );
    });

    test('rejects a name that does not match the generated shape', () {
      expect(() => engine.validateFileName('not_a_backup.db'), throwsA(isA<InvalidBackupFileName>()));
    });
  });

  group('sortNewestFirst', () {
    test('orders by createdAt, not by filename string', () {
      final older = BackupMetadata(fileName: 'fulus_manual_20260101_000000.db', label: 'manual', createdAt: DateTime.utc(2026, 1, 1), sizeBytes: 10);
      final newer = BackupMetadata(fileName: 'fulus_scheduled_20260201_000000.db', label: 'scheduled', createdAt: DateTime.utc(2026, 2, 1), sizeBytes: 10);
      final sorted = engine.sortNewestFirst([older, newer]);
      expect(sorted.first, newer);
      expect(sorted.last, older);
    });
  });

  group('selectPruneCandidates', () {
    List<BackupMetadata> scheduledBackups(int count) => List.generate(
          count,
          (i) => BackupMetadata(
            fileName: 'fulus_scheduled_2026010${i + 1}_000000.db',
            label: 'scheduled',
            createdAt: DateTime.utc(2026, 1, i + 1),
            sizeBytes: 10,
          ),
        );

    test('returns nothing to prune when at or under the keep count', () {
      expect(engine.selectPruneCandidates(scheduledBackups(14), keep: 14), isEmpty);
    });

    test('selects only the oldest excess scheduled backups beyond keep', () {
      final backups = scheduledBackups(16);
      final candidates = engine.selectPruneCandidates(backups, keep: 14);
      expect(candidates.length, 2);
      // The two oldest (day 1 and day 2) should be selected, not the newest.
      expect(candidates.map((b) => b.createdAt.day), containsAll([1, 2]));
    });

    test('never selects manual or pre_restore_safety backups regardless of count', () {
      final manual = List.generate(
        20,
        (i) => BackupMetadata(fileName: 'fulus_manual_2026010${i % 9 + 1}_000000.db', label: 'manual', createdAt: DateTime.utc(2026, 1, i + 1), sizeBytes: 10),
      );
      expect(engine.selectPruneCandidates(manual, keep: 14), isEmpty);
    });
  });
}
