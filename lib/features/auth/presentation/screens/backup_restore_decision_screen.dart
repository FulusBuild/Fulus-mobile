import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../app/providers.dart';
import '../../../../core/errors/module_failures.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/backup_record.dart';
import '../../../../shared/widgets/widgets.dart';
import 'auth_gate_screen.dart';

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
/// Also reachable directly from [GetStartedScreen]'s own "Restore from
/// a backup" link — the case [AuthGateScreen]'s automatic check can
/// never catch: a real uninstall/reinstall wipes this app's own backups
/// folder along with everything else, so there is nothing for that
/// check to find, ever, no matter what lives in it. This screen still
/// works fine reached that way — `newest` is simply null, "Choose a
/// backup file" is the only backup-shaped button, and [_startFresh]
/// still leads to the same place — see the headline text above for the
/// one line of copy that actually depends on which of the two ways in
/// was used.
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
/// reached — so it's a plain navigation, not a destructive,
/// confirm-gated action. See [_startFresh]'s own doc comment for why
/// that navigation goes through [ScreenExit.closeScreenOr] and not a
/// bare `context.go('/')`.
///
/// **Detection, take two.** [BackupRepository.listBackups] only ever
/// sees this app's own sandboxed folder, which a real uninstall wipes
/// along with everything else — so on a genuine reinstall, "detected
/// automatically" used to mean nothing ever, no matter what backups a
/// person actually had. [BackupRepository.findDurableBackup] closes
/// that gap by reading back the one copy [BackupRepository.exportToDownloads]
/// already writes somewhere a reinstall can't touch (public Downloads,
/// via MediaStore) — checked here, and by [AuthGateScreen] itself, so
/// this really is automatic now for anyone whose device ever ran an
/// auto-backup, not just a better-labeled manual picker.
class BackupRestoreDecisionScreen extends ConsumerStatefulWidget {
  const BackupRestoreDecisionScreen({super.key});

  @override
  ConsumerState<BackupRestoreDecisionScreen> createState() => _BackupRestoreDecisionScreenState();
}

class _BackupRestoreDecisionScreenState extends ConsumerState<BackupRestoreDecisionScreen> {
  // Cached once, same reasoning as every other auth screen's own
  // late-final future (AuthGateScreen, RestoreProgressScreen).
  //
  // Gap fix: this used to be `listBackups()` alone, which only ever
  // checks this app's own sandboxed folder — exactly what a real
  // uninstall/reinstall wipes (see the class doc comment above and
  // BackupRepository.exportToDownloads' own doc comment). The one
  // copy actually designed to survive that is the durable Downloads
  // export [BackupRepository.findDurableBackup] reads back — checked
  // here too, but only once [listBackups] itself comes back empty, to
  // avoid a pointless extra native round-trip on the far more common
  // path where this app's own folder already has something in it.
  late final Future<({List<BackupMetadata> local, BackupMetadata? durable, String? durablePath})>
      _detectedFuture = _detect();

  bool _busy = false;
  String? _error;

  Future<({List<BackupMetadata> local, BackupMetadata? durable, String? durablePath})> _detect() async {
    final repo = ref.read(backupRepositoryProvider);
    final local = await repo.listBackups();
    if (local.isNotEmpty) return (local: local, durable: null, durablePath: null);

    final durablePath = await repo.findDurableBackup();
    if (durablePath == null) return (local: local, durable: null, durablePath: null);

    // findDurableBackup already copied this out to a plain,
    // dart:io-readable path (see its own doc comment for why a
    // MediaStore URI can't be stat'd directly) — reading it back here
    // mirrors exactly what listBackups does for its own files, so the
    // detected-backup card reads the same regardless of which source
    // found it.
    final stat = await File(durablePath).stat();
    final durable = BackupMetadata(
      fileName: p.basename(durablePath),
      label: 'auto',
      createdAt: stat.modified.toUtc(),
      sizeBytes: stat.size,
    );
    return (local: local, durable: durable, durablePath: durablePath);
  }

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

  /// The one-tap counterpart to [_pickAndRestore] for a backup
  /// [_detect] already found on its own — [path] is the plain local
  /// copy [BackupRepository.findDurableBackup] made from the Downloads
  /// export. Goes through the exact same [BackupRepository.importBackupFile]
  /// validation and copy-in a manually picked file gets, then the same
  /// [_restore] every other path here ends at — the person never sees
  /// a difference beyond not having to open a file browser for it.
  Future<void> _restoreDurable(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imported = await ref.read(backupRepositoryProvider).importBackupFile(path);
      if (!mounted) return;
      await _restore(imported.metadata.fileName);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is BackupException ? e.message : "Couldn't read that backup.";
      });
    }
  }

  Future<void> _pickAndRestore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Same initialDirectory hint as BackupScreen's own picker call —
      // see BackupRepository.initialRestoreDirectory's doc comment.
      final initialDirectory = await ref.read(backupRepositoryProvider).initialRestoreDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        initialDirectory: initialDirectory,
      );
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

  /// Bug fix (round 2): `context.go('/')` alone — the original fix
  /// here — only ever updates go_router's own state at that location;
  /// it never touches a plain `Navigator` stack. That's invisible when
  /// this screen is reached the way [AuthGateScreen] reaches it (built
  /// straight in place at `/`, nothing pushed) — `go('/')` and a
  /// rebuild are all there is to undo. But this screen's *other* entry
  /// point, [GetStartedScreen]'s own "Restore from a backup" link, is
  /// a real `Navigator.push` — and `go('/')` from there just updates
  /// the state sitting *underneath* that pushed screen, which stays on
  /// top, fully visible, un-popped. Tapping "Start Fresh" from that
  /// path did exactly nothing the person could see: the exact "phantom
  /// dead end" [ScreenExit.closeScreenOr]'s own doc comment describes,
  /// just reached from the opposite direction (an unpopped push, not
  /// an unrunnable pop). `closeScreenOr` handles both of this screen's
  /// entry points correctly by construction — pops the pushed instance
  /// when there's a real `Navigator` entry to pop, falls back to
  /// `go('/')` exactly as before when there isn't.
  void _startFresh() {
    context.closeScreenOr('/');
  }

  @override
  Widget build(BuildContext context) {
    // See BackGuard's own doc comment: this screen is reached both by
    // a raw Navigator.push (GetStartedScreen's "Restore from a
    // backup") and rendered in place with nothing pushed at all
    // (AuthGateScreen auto-detecting a backup) — never through a real
    // go_router route — so hardware back / gesture nav, and the pop
    // notification Android redelivers when file_picker's document-
    // picker Activity returns control here, both need the same guard
    // _startFresh's own button now uses, or they crash inside
    // go_router's delegate instead of just failing a button tap.
    return BackGuard(
      fallbackLocation: '/',
      child: FulusScreen(
        body: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: FutureBuilder<({List<BackupMetadata> local, BackupMetadata? durable, String? durablePath})>(
                future: _detectedFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: FulusLoadingIndicator(),
                    );
                  }
                  final detected = snapshot.data!;
                  final newest = detected.local.isEmpty ? null : detected.local.first;
                  final durable = detected.durable;
                  final durablePath = detected.durablePath;
                  final somethingDetected = newest != null || durable != null;
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
                        // Reachable three ways now: AuthGateScreen
                        // auto-detecting a backup in this app's own
                        // folder (newest != null), AuthGateScreen (or
                        // GetStartedScreen's link) finding nothing
                        // local but a durable Downloads copy instead
                        // (durable != null — see findDurableBackup's
                        // own doc comment for why that one alone
                        // survives a real reinstall), or genuinely
                        // nothing at all, which only GetStartedScreen's
                        // link can still reach a person from.
                        newest != null
                            ? 'We found backup data on this device.'
                            : durable != null
                                ? 'We found a backup saved to your Downloads folder.'
                                : 'Restore from a backup file, or start fresh.',
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
                        )
                      else if (durable != null)
                        FulusCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _DetectedRow(label: 'Backup', value: 'Downloads/Fulus'),
                              const SizedBox(height: AppSpacing.sm),
                              _DetectedRow(label: 'Created', value: _dateDisplay(durable.createdAt)),
                            ],
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      if (newest != null)
                        FulusActionTile(
                          label: 'Restore this backup',
                          subtitle: 'Use the backup we found on this device.',
                          icon: Icons.restore_rounded,
                          trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                          onTap: _busy ? null : () => _restore(newest.fileName),
                        )
                      else if (durablePath != null)
                        FulusActionTile(
                          label: 'Restore saved backup',
                          subtitle: 'Use the backup found in Downloads.',
                          icon: Icons.restore_rounded,
                          trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                          onTap: _busy ? null : () => _restoreDurable(durablePath),
                        ),
                      if (newest != null || durablePath != null) const SizedBox(height: AppSpacing.sm),
                      FulusActionTile(
                        label: somethingDetected ? 'Choose a different file' : 'Choose a backup file',
                        subtitle: 'Select a Fulus backup from your device storage.',
                        icon: Icons.folder_open_rounded,
                        onTap: _busy ? null : _pickAndRestore,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FulusActionTile(
                        label: 'Start fresh',
                        subtitle: 'Set up Fulus without restoring a backup.',
                        icon: Icons.restart_alt_rounded,
                        onTap: _busy ? null : _startFresh,
                      ),
                    ],
                  );
                },
              ),
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
      case 'auto':
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
