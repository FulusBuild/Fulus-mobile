import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/module_failures.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/formatting.dart';
import '../../../../../domain/entities/backup_record.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Implementation Bible: "Backup is local. Backup creates SQLite
/// snapshots. Restore replaces database. Export uses Android Share
/// Sheet. No server." This screen is a direct front-end for
/// BackupRepository's five operations — no logic of its own.
///
/// Backup & Restore (schemaVersion 10) adds a sixth: "Restore from a
/// file" alongside "Back up now" — [FilePicker], the same call shape
/// `bulk_import_screen.dart` already uses, reaching anywhere Android's
/// document picker can (an SD card, a cloud-sync folder, an email
/// attachment) rather than only the backups this app already knows
/// about below. This is the in-app half of "the user should be able to
/// pick a backup file from storage" — BackupRestoreDecisionScreen (the
/// onboarding-time flow, for a fresh install with no signed-in owner
/// yet) is the other half, for before this screen is even reachable.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<BackupMetadata>> _future;
  late final Future<String> _dirFuture = ref.read(backupRepositoryProvider).backupDirectoryPath();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backupRepositoryProvider).listBackups();
  }

  void _reload() => setState(() {
        _future = ref.read(backupRepositoryProvider).listBackups();
      });

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _showError(e.message);
    } on InvalidBackupFileName catch (e) {
      _showError(e.message);
    } finally {
      // _reload() itself calls setState — if the widget was disposed
      // while `action` was in flight (user navigated away mid-backup),
      // calling it unconditionally would throw "setState() called
      // after dispose()". Both post-action updates share this one guard.
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  void _showError(String message) {
    if (mounted) showFulusSnackbar(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: FulusButton(
                    label: _busy ? 'Working…' : 'Back up now',
                    icon: Icons.backup_outlined,
                    loading: _busy,
                    onPressed: _busy ? () {} : () => _runBusy(() => ref.read(backupRepositoryProvider).createBackup(label: 'manual')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FulusButton(
                    label: 'Restore from a file',
                    icon: Icons.file_open_outlined,
                    variant: FulusButtonVariant.secondary,
                    onPressed: _busy ? () {} : _pickAndImport,
                  ),
                ),
              ],
            ),
          ),
          // Discoverability fix: "I don't know where it saves to" had
          // no real answer before this — this is that answer, always
          // visible rather than something the person has to go looking
          // for. Also covers the two automatic backups now running in
          // the background: the activity-triggered local one
          // (BackupRepository.runAutoBackup, kicked off by
          // AutoBackupGate) and the copy it mirrors into Downloads on
          // every run (BackupRepository.exportToDownloads) — the one
          // of the two that actually survives a reinstall, since this
          // folder, wherever it lives, does not (see
          // BackupRepository.exportToDownloads' own doc comment).
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: FutureBuilder<String>(
              future: _dirFuture,
              builder: (context, snapshot) {
                final path = snapshot.data;
                return Text(
                  path == null
                      ? 'Fulus also backs itself up automatically as you use the app, '
                          'with a copy kept in Downloads/Fulus that survives a reinstall.'
                      : 'Saved to $path, and automatically as you use the app — with a '
                          'copy kept in Downloads/Fulus that survives a reinstall.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                );
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<BackupMetadata>>(
              future: _future,
              builder: (context, snapshot) {
                final backups = snapshot.data ?? const [];
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (backups.isEmpty) {
                  return const FulusEmptyState(
                    icon: Icons.backup_outlined,
                    headline: 'No backups yet.',
                    body: 'Back up now to keep a local snapshot you can restore from later.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _BackupTile(
                    backup: backups[i],
                    busy: _busy,
                    onRestore: () => _confirmRestore(backups[i]),
                    onShare: () => _share(backups[i]),
                    onDelete: () => _runBusy(() => ref.read(backupRepositoryProvider).deleteBackup(backups[i].fileName)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BackupMetadata backup) async {
    try {
      final path = await ref.read(backupRepositoryProvider).prepareForShare(backup.fileName);
      if (!mounted) return;
      // See pubspec.yaml's comment on the share_plus version pin — this
      // uses the long-stable Share.shareXFiles API deliberately.
      // SharePlus.instance.share() has open bugs on platforms this app
      // targets: broken entirely on Windows (plus_plugins#3619) and
      // throws/hangs on iOS 26 (plus_plugins#3685, #3631). Revisit once
      // those are resolved upstream.
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(path)], text: 'Fulus backup: ${backup.fileName}');
    } on BackupException catch (e) {
      _showError(e.message);
    } on InvalidBackupFileName catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _confirmRestore(BackupMetadata backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'This replaces everything currently in the app with the contents of "${backup.fileName}". '
          'A safety copy of what\'s here now will be taken first, so this can be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed == true) {
      await _runBusy(() => ref.read(backupRepositoryProvider).restoreBackup(backup.fileName));
    }
  }

  /// Same [showFulusConfirmDialog] Component Library 5.9 pattern this
  /// screen's own [_confirmRestore] already uses for the same reason —
  /// this is at least as destructive (it replaces the live database
  /// too, right after copying the picked file in), so it needs the
  /// same confirmation, not a lighter one just because the source is a
  /// picked file instead of one already in the list below.
  Future<void> _pickAndImport() async {
    // Points the system document picker at wherever a backup is
    // actually most likely to be sitting — see initialRestoreDirectory's
    // own doc comment on why that's not always this app's own folder.
    // Best-effort: Android's picker treats this as a hint, not a
    // guarantee, which is exactly why the folder is also shown
    // permanently above rather than relying on this alone.
    final initialDirectory = await ref.read(backupRepositoryProvider).initialRestoreDirectory();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      initialDirectory: initialDirectory,
    );
    if (result.isEmpty || !mounted) return; // canceled
    final path = result.single.path;
    if (path == null) {
      _showError("Couldn't read that file.");
      return;
    }
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Restore from this file?',
      message: 'This replaces everything currently in the app with the contents of this file. '
          'A safety copy of what\'s here now will be taken first, so this can be undone.',
      confirmLabel: 'Restore',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final imported = await ref.read(backupRepositoryProvider).importBackupFile(path);
      await ref.read(backupRepositoryProvider).restoreBackup(imported.metadata.fileName);
    });
  }
}

/// Same mapping as BackupRestoreDecisionScreen's own `_labelDisplay` —
/// kept in sync by hand rather than shared, since the two screens
/// already had zero shared imports before this and a two-case switch
/// isn't worth a new shared file over. 'auto' reads the same as
/// 'scheduled' here too, for the same reason: both are backups the
/// person didn't have to think about, which is the one thing this
/// label is actually telling them.
String _labelDisplay(String label) {
  switch (label) {
    case 'scheduled':
    case 'auto':
      return 'Automatic backup';
    case 'imported':
      return 'Imported backup';
    case 'pre_restore_safety':
      return 'Safety snapshot';
    default:
      return 'Manual backup';
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.busy,
    required this.onRestore,
    required this.onShare,
    required this.onDelete,
  });

  final BackupMetadata backup;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sizeKb = (backup.sizeBytes / 1024).toStringAsFixed(0);
    final createdAt = backup.createdAt.toLocal();
    return FulusCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_labelDisplay(backup.label), style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${formatRelativeDay(createdAt)} · ${formatTime(createdAt)} · $sizeKb KB',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (action) {
              switch (action) {
                case 'restore':
                  onRestore();
                case 'share':
                  onShare();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'restore', child: Text('Restore')),
              PopupMenuItem(value: 'share', child: Text('Share / Export')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
