import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/module_failures.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/backup_record.dart';
import '../../../../shared/widgets/widgets.dart';
import 'auth_gate_screen.dart';
import 'get_started_screen.dart';

/// Shown by [AuthGateScreen] (via `resolveAuthGateStage` in
/// core/onboarding/onboarding_routing.dart) for the state Backup &
/// Restore's own task requirement names directly: a fresh install —
/// no owner account, no business configured locally — that nonetheless
/// has at least one backup file sitting in this app's own backups
/// folder ([BackupRepository.listBackups]). Reads as "Restore or start
/// fresh," per that requirement, rather than silently funneling what
/// might be a genuine reinstall into recreating the business from
/// scratch.
///
/// Two ways to restore, both ending at the same [_restore]:
/// - **the detected backup itself** — the newest file this screen's own
///   `listBackups` call already found, one tap away.
/// - **Choose a different file** — [FilePicker], the same call shape
///   `bulk_import_screen.dart` already uses for CSV, here filtered to
///   `.db`. This is the actual "pick a backup file from storage"
///   capability: it reaches anywhere Android's own document picker
///   can — an SD card, a cloud-sync app's local folder, a file saved
///   from an email attachment — not just this app's own folder, which
///   matters specifically because that folder is exactly what does NOT
///   reliably survive an uninstall (see backup_repository_impl.dart's
///   own doc comment on why `getApplicationDocumentsDirectory` is used
///   for it anyway: it's the right place for same-session backups,
///   just not a durable one on its own). A picked file goes through
///   [BackupRepository.importBackupFile] first — copied in under a
///   fresh compliant name — before the same [_restore] call every
///   other path here uses.
///
/// **Start Fresh** has nothing to wipe at this stage (unlike
/// [RestoreProgressScreen]'s own Start Fresh) — no owner account and no
/// business exist yet by construction of how this screen is even
/// reached — so it's a plain navigation to [GetStartedScreen], not a
/// destructive, confirm-gated action.
class BackupRestoreDecisionScreen extends ConsumerStatefulWidget {
  const BackupRestoreDecisionScreen({super.key});

  @override
  ConsumerState<BackupRestoreDecisionScreen> createState() => _BackupRestoreDecisionScreenState();
}

class _BackupRestoreDecisionScreenState extends ConsumerState<BackupRestoreDecisionScreen> {
  // Cached once, same reasoning as every other auth screen's own
  // late-final future (AuthGateScreen, RestoreProgressScreen).
  late final Future<List<BackupMetadata>> _detectedFuture =
      ref.read(backupRepositoryProvider).listBackups();
  bool _busy = false;
  String? _error;

  Future<void> _restore(String fileName) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backupRepositoryProvider).restoreBackup(fileName);
      if (!mounted) return;
      // Same "this screen is no longer a valid place to come back to"
      // reasoning as RestoreProgressScreen's own Start Fresh —
      // AuthGateScreen re-evaluates from scratch and now finds a real
      // owner account, routing itself to IdentityPickerScreen.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGateScreen()),
        (route) => false,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is BackupException
            ? e.message
            : e is InvalidBackupFileName
                ? 'That backup file looks invalid.'
                : "Couldn't restore that backup.";
      });
    }
  }

  Future<void> _pickAndRestore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['db']);
      if (result.isEmpty) {
        setState(() => _busy = false);
        return; // canceled
      }
      final path = result.single.path;
      if (path == null) {
        setState(() {
          _busy = false;
          _error = "Couldn't read that file.";
        });
        return;
      }
      final imported = await ref.read(backupRepositoryProvider).importBackupFile(path);
      if (!mounted) return;
      await _restore(imported.metadata.fileName);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is BackupException ? e.message : "Couldn't read that file.";
      });
    }
  }

  void _startFresh() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const GetStartedScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: FutureBuilder<List<BackupMetadata>>(
              future: _detectedFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: FulusLoadingIndicator(),
                  );
                }
                final backups = snapshot.data!;
                final newest = backups.isEmpty ? null : backups.first;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We found backup data on this device.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (newest != null)
                      FulusCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DetectedRow(label: 'Backup', value: _labelDisplay(newest.label)),
                            const SizedBox(height: AppSpacing.sm),
                            _DetectedRow(label: 'Created', value: _dateDisplay(newest.createdAt)),
                          ],
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    if (newest != null)
                      FulusButton(
                        label: 'Restore from backup',
                        loading: _busy,
                        loadingLabel: 'Restoring',
                        onPressed: _busy ? null : () => _restore(newest.fileName),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    FulusButton(
                      label: newest == null ? 'Choose a backup file' : 'Choose a different file',
                      variant: newest == null ? FulusButtonVariant.primary : FulusButtonVariant.secondary,
                      loading: _busy && newest == null,
                      onPressed: _busy ? null : _pickAndRestore,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FulusButton(
                      label: 'Start Fresh',
                      variant: FulusButtonVariant.text,
                      onPressed: _busy ? null : _startFresh,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _labelDisplay(String label) {
    switch (label) {
      case 'imported':
        return 'Imported backup';
      case 'scheduled':
        return 'Automatic backup';
      case 'pre_restore_safety':
        return 'Safety snapshot';
      default:
        return 'Manual backup';
    }
  }

  String _dateDisplay(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _DetectedRow extends StatelessWidget {
  const _DetectedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
