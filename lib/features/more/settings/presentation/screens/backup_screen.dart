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
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<BackupMetadata>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backupRepositoryProvider).listBackups();
  }

  void _reload() => setState(() => _future = ref.read(backupRepositoryProvider).listBackups());

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
            child: FulusButton(
              label: _busy ? 'Working…' : 'Back up now',
              icon: Icons.backup_outlined,
              loading: _busy,
              onPressed: _busy ? () {} : () => _runBusy(() => ref.read(backupRepositoryProvider).createBackup(label: 'manual')),
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
      // ignore: deprecated_member_use — SharePlus.instance.share() has open
      // bugs on platforms this app targets: broken entirely on Windows
      // (plus_plugins#3619) and throws/hangs on iOS 26 (plus_plugins#3685,
      // #3631). Revisit once those are resolved upstream.
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
                Text(backup.label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
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
