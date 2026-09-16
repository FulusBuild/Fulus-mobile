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
  late final Future<String> _dirFuture = ref.read(backupRepositoryProvider).backupDirectoryPath();
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FulusCard(
              elevated: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 560;
                  final children = [
                    Expanded(child: FulusButton(label: _busy ? 'Working…' : 'Back up now', icon: Icons.backup_outlined, loading: _busy, onPressed: _busy ? null : () => _runBusy(() => ref.read(backupRepositoryProvider).createBackup(label: 'manual')))),
                    if (!stacked) const SizedBox(width: AppSpacing.sm),
                    if (stacked) const SizedBox(height: AppSpacing.sm),
                    Expanded(child: FulusButton(label: 'Restore from a file', icon: Icons.file_open_outlined, variant: FulusButtonVariant.secondary, onPressed: _busy ? null : _pickAndImport)),
                  ];
                  return stacked ? Column(children: children) : Row(children: children);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FutureBuilder<String>(
              future: _dirFuture,
              builder: (context, snapshot) => FulusCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.folder_outlined, color: AppColors.primaryOf(context)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(snapshot.data == null ? 'Automatic backups are kept locally, with a copy in Downloads/Fulus that survives a reinstall.' : 'Saved to ${snapshot.data}\nAutomatic backups also keep a copy in Downloads/Fulus.', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)))),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<BackupMetadata>>(
              future: _future,
              builder: (context, snapshot) {
                final backups = snapshot.data ?? const [];
                if (!snapshot.hasData) return const FulusLoadingIndicator();
                if (backups.isEmpty) return const FulusEmptyState(icon: Icons.backup_outlined, headline: 'No backups yet', body: 'Back up now to keep a local snapshot you can restore later.');
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _BackupTile(backup: backups[i], busy: _busy, onRestore: () => _confirmRestore(backups[i]), onShare: () => _share(backups[i]), onDelete: () => _runBusy(() => ref.read(backupRepositoryProvider).deleteBackup(backups[i].fileName))),
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
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(path)], text: 'Fulus backup: ${backup.fileName}');
    } on BackupException catch (e) {
      _showError(e.message);
    } on InvalidBackupFileName catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _confirmRestore(BackupMetadata backup) async {
    final confirmed = await showFulusConfirmDialog(context, title: 'Restore this backup?', message: 'This replaces the current app data with "${backup.fileName}". A safety copy is taken first.', confirmLabel: 'Restore');
    if (confirmed) await _runBusy(() => ref.read(backupRepositoryProvider).restoreBackup(backup.fileName));
  }

  Future<void> _pickAndImport() async {
    final initialDirectory = await ref.read(backupRepositoryProvider).initialRestoreDirectory();
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['db'], initialDirectory: initialDirectory);
    if (result.isEmpty || !mounted) return;
    final path = result.single.path;
    if (path == null) {
      _showError("Couldn't read that file.");
      return;
    }
    final confirmed = await showFulusConfirmDialog(context, title: 'Restore from this file?', message: 'This replaces the current app data with the contents of this file. A safety copy is taken first.', confirmLabel: 'Restore');
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final imported = await ref.read(backupRepositoryProvider).importBackupFile(path);
      await ref.read(backupRepositoryProvider).restoreBackup(imported.metadata.fileName);
    });
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
  const _BackupTile({required this.backup, required this.busy, required this.onRestore, required this.onShare, required this.onDelete});
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
          Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.selectedTintOf(context), borderRadius: BorderRadius.circular(AppRadius.md)), child: Icon(Icons.backup_outlined, color: AppColors.primaryOf(context))),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_labelDisplay(backup.label), style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)), Text('${formatRelativeDay(createdAt)} · ${formatTime(createdAt)} · $sizeKb KB', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)))])),
          PopupMenuButton<String>(enabled: !busy, onSelected: (action) { switch (action) { case 'restore': onRestore(); case 'share': onShare(); case 'delete': onDelete(); } }, itemBuilder: (context) => const [PopupMenuItem(value: 'restore', child: Text('Restore')), PopupMenuItem(value: 'share', child: Text('Share / Export')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
        ],
      ),
    );
  }
}
