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

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<BackupMetadata>> _future;
  late final Future<String> _dirFuture =
      ref.read(backupRepositoryProvider).backupDirectoryPath();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(backupRepositoryProvider).listBackups();
  }

  void _reload() => setState(
        () => _future = ref.read(backupRepositoryProvider).listBackups(),
      );

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _showError(e.message);
    } on InvalidBackupFileName catch (e) {
      _showError(e.message);
    } finally {
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
    return FulusScreen(
      title: 'Backup & Restore',
      subtitle: 'Keep a local copy of your business data',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final horizontal = wide ? AppSpacing.lg : AppSpacing.xs;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.sm,
              horizontal,
              AppSpacing.xxl,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FulusCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primaryOf(context)
                                    .withValues(alpha: 0.10),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                              ),
                              child: Icon(
                                Icons.backup_outlined,
                                color: AppColors.primaryOf(context),
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Local backup',
                                    style: AppTypography.heading.copyWith(
                                      color: AppColors.textPrimaryOf(context),
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Fulus keeps your business local-first. Create a snapshot whenever you want, then restore it on this device later.',
                                    style: AppTypography.body.copyWith(
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const FulusSectionHeader(
                        title: 'Backup',
                        subtitle: 'Create a snapshot or restore an existing one',
                      ),
                      FulusCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _ActionRow(
                              icon: Icons.backup_outlined,
                              title: 'Back up now',
                              subtitle: _busy
                                  ? 'Creating a safety snapshot…'
                                  : 'Create a fresh copy of your current business data',
                              onTap: _busy
                                  ? null
                                  : () => _runBusy(
                                        () => ref
                                            .read(backupRepositoryProvider)
                                            .createBackup(label: 'manual'),
                                      ),
                            ),
                            const FulusListDivider(),
                            _ActionRow(
                              icon: Icons.file_open_outlined,
                              title: 'Restore from a file',
                              subtitle: 'Import a .db backup from your device',
                              onTap: _busy ? null : _pickAndImport,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FutureBuilder<String>(
                        future: _dirFuture,
                        builder: (context, snapshot) => FulusCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                color: AppColors.primaryOf(context),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  snapshot.data == null
                                      ? 'Automatic backups are kept locally, with a copy in Downloads/Fulus that survives a reinstall.'
                                      : 'Saved to ${snapshot.data}\nAutomatic backups also keep a copy in Downloads/Fulus.',
                                  style: AppTypography.caption.copyWith(
                                    color:
                                        AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const FulusSectionHeader(
                        title: 'Saved backups',
                        subtitle: 'Snapshots available to restore or export',
                      ),
                      FutureBuilder<List<BackupMetadata>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return FulusErrorState(
                              message: "Couldn't load your backups.",
                              onRetry: _reload,
                            );
                          }
                          final backups = snapshot.data;
                          if (backups == null) {
                            return const FulusLoadingIndicator();
                          }
                          if (backups.isEmpty) {
                            return const FulusEmptyState(
                              icon: Icons.backup_outlined,
                              headline: 'No backups yet',
                              body:
                                  'Back up now to keep a local snapshot you can restore later.',
                            );
                          }
                          return Column(
                            children: [
                              for (var i = 0; i < backups.length; i++) ...[
                                _BackupTile(
                                  backup: backups[i],
                                  busy: _busy,
                                  onRestore: () =>
                                      _confirmRestore(backups[i]),
                                  onShare: () => _share(backups[i]),
                                  onDelete: () => _runBusy(
                                    () => ref
                                        .read(backupRepositoryProvider)
                                        .deleteBackup(backups[i].fileName),
                                  ),
                                ),
                                if (i != backups.length - 1)
                                  const SizedBox(height: AppSpacing.sm),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _share(BackupMetadata backup) async {
    try {
      final path = await ref
          .read(backupRepositoryProvider)
          .prepareForShare(backup.fileName);
      if (!mounted) return;
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Fulus backup: ${backup.fileName}',
      );
    } on BackupException catch (e) {
      _showError(e.message);
    } on InvalidBackupFileName catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _confirmRestore(BackupMetadata backup) async {
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          'This replaces the current app data with "${backup.fileName}". A safety copy is taken first.',
      confirmLabel: 'Restore',
    );
    if (confirmed) {
      await _runBusy(
        () => ref.read(backupRepositoryProvider).restoreBackup(backup.fileName),
      );
    }
  }

  Future<void> _pickAndImport() async {
    final initialDirectory =
        await ref.read(backupRepositoryProvider).initialRestoreDirectory();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      initialDirectory: initialDirectory,
    );
    if (result.isEmpty || !mounted) return;
    final path = result.single.path;
    if (path == null) {
      _showError("Couldn't read that file.");
      return;
    }
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Restore from this file?',
      message:
          'This replaces the current app data with the contents of this file. A safety copy is taken first.',
      confirmLabel: 'Restore',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final imported =
          await ref.read(backupRepositoryProvider).importBackupFile(path);
      await ref
          .read(backupRepositoryProvider)
          .restoreBackup(imported.metadata.fileName);
    });
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FulusListRow(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.selectedTintOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              Icons.backup_outlined,
              color: AppColors.primaryOf(context),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelDisplay(backup.label),
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatRelativeDay(createdAt)} · ${formatTime(createdAt)} · $sizeKb KB',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
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
