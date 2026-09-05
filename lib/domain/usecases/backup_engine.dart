import '../../core/errors/module_failures.dart';
import '../entities/backup_record.dart';

/// Stage 10's pure-logic layer. No dart:io, no sqlite3, no Flutter —
/// only filename generation/parsing, prune selection, and the path-
/// traversal guard, so all of it is directly unit-testable and so
/// BackupRepositoryImpl (the only place touching real files) stays a
/// thin adapter around this.
///
/// 'imported' (Backup & Restore, schemaVersion 10) is a fourth label —
/// a file the user picked from outside this device's own backups
/// folder (BackupRepository.importBackupFile), copied in under a fresh
/// compliant name so it can go through the exact same [validateFileName]
/// / restoreBackup path every other backup does. Never auto-pruned by
/// [selectPruneCandidates], same as 'manual' and 'pre_restore_safety' —
/// something the user explicitly brought in from elsewhere is exactly
/// as deliberate a keep as a manual backup they made themselves.
class BackupEngine {
  const BackupEngine();

  static const _validLabels = {'manual', 'scheduled', 'pre_restore_safety', 'imported', 'auto'};

  /// BUG FIX (integration pass): this used to say "mirrors
  /// backup_service.create_backup's filename format exactly:
  /// bms_{label}_{yyyyMMdd_HHmmss}.db" — that WAS the backend's format,
  /// before the BMS -> Fulus rename changed it to fulus_{label}_{ts}.db
  /// (with backward-compat recognition of pre-rename bms_*.db files —
  /// see backup_service.py's own _LEGACY_BACKUP_PREFIX). This module was
  /// evidently written against a pre-rename copy of that file. New
  /// backups from this device now use the current, correct prefix;
  /// [validateFileName] below still recognizes the legacy one too, for
  /// the same reason the backend does — not because this specific
  /// mobile engine has any real pre-rename files anywhere (it doesn't;
  /// it's new), but because a bare filename this permissive costs
  /// nothing extra to accept and keeps this module's own rule in sync
  /// with the backend's actual current one, which is the real
  /// specification per this project's own stated guiding principle.
  String buildFileName({required String label, required DateTime createdAtUtc}) {
    if (!_validLabels.contains(label)) {
      throw BackupException('Unknown backup label "$label".');
    }
    final ts = _formatTimestamp(createdAtUtc);
    return 'fulus_${label}_$ts.db';
  }

  String _formatTimestamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        '_${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }

  /// mirrors both restore_backup's and delete_backup's identical
  /// "basic security" guard: the name must be a bare filename matching
  /// either the current (fulus_*.db) or legacy (bms_*.db) shape this
  /// project's backup files can have — no path separators, no '..',
  /// nothing that could resolve outside the backup directory. Backend
  /// enforces this by resolving the path and checking it's still inside
  /// the backup dir; a bare filename check achieves the identical result
  /// without needing real filesystem access, which is what keeps this
  /// method pure.
  void validateFileName(String fileName) {
    final pattern = RegExp(r'^(fulus|bms)_[a-zA-Z0-9_]+_\d{8}_\d{6}\.db$');
    if (fileName.contains('/') ||
        fileName.contains('\\') ||
        fileName.contains('..') ||
        !pattern.hasMatch(fileName)) {
      throw InvalidBackupFileName(fileName);
    }
  }

  /// True chronological order (parsed from the embedded timestamp),
  /// newest first.
  ///
  /// Deliberate deviation from backup_service.list_backups(), which
  /// sorts by the raw filename string. Because the label sits BEFORE
  /// the timestamp in `fulus_{label}_{ts}.db`, a plain string sort orders
  /// primarily by label name ("manual" before "scheduled"
  /// alphabetically) and only falls back to timestamp order within the
  /// same label — so a `manual` backup from today can sort after a
  /// `scheduled` one from last month. The product intent ("show
  /// backups newest first") is unambiguous even where the backend's
  /// literal sort key isn't; this is the one place in this module where
  /// the two disagree, per the standing rule that business intent wins.
  List<BackupMetadata> sortNewestFirst(List<BackupMetadata> backups) {
    final copy = [...backups];
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  /// mirrors _prune_old_backups exactly: only ever prunes files with
  /// the given [label] (manual and pre_restore_safety backups are
  /// never auto-deleted, since neither is ever passed here), keeping
  /// the [keep] most recent by timestamp and returning the rest for
  /// deletion. [label] defaults to 'scheduled' — [runScheduledBackup]'s
  /// own long-standing behavior, so every existing call site is
  /// unaffected. [runAutoBackup] is the other caller, passing 'auto'
  /// with `keep: 1` so the always-current, activity-triggered backup
  /// stays exactly one file on disk — same prune-after-create shape as
  /// the scheduled flow, just with a keep count of 1 instead of many.
  List<BackupMetadata> selectPruneCandidates(
    List<BackupMetadata> backups, {
    String label = 'scheduled',
    int keep = 14,
  }) {
    final matching = sortNewestFirst(backups.where((b) => b.label == label).toList());
    if (matching.length <= keep) return const [];
    return matching.sublist(keep);
  }
}
