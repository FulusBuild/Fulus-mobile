import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../../sync/sync_status.dart';

/// Gap fix — Volume 12's Sync Detail screen didn't exist at all; the
/// full sync engine (retry policy, conflict resolver, sync queue,
/// SyncStatusNotifier) was built with nothing in the UI ever reading
/// it. Reached by tapping the persistent indicator (see app_shell.dart's
/// `_SyncStatusIndicator`) or from Settings.
class SyncDetailScreen extends ConsumerWidget {
  const SyncDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncConfig = ref.watch(syncConfigProvider);
    final statusAsync = ref.watch(_syncDetailStatusProvider);

    return FulusScreen(
      title: 'Sync & backup',
      body: ListView(
        children: [
          FulusSectionHeader(title: 'Status'),
          statusAsync.when(
            data: (status) => _StatusCard(status: status, syncEnabled: syncConfig.isEnabled),
            loading: () => const FulusLoadingIndicator(),
            error: (_, __) => FulusErrorState(
              message: "Couldn't read sync status.",
              onRetry: () => ref.invalidate(_syncDetailStatusProvider),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (syncConfig.isEnabled && statusAsync.value?.kind != SyncStatusKind.disabled) ...[
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Sync now',
                onPressed: () => _syncNow(context, ref),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          FulusSectionHeader(title: 'Settings'),
          FulusCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: syncConfig.isEnabled,
              onChanged: (value) => _setEnabled(context, ref, value),
              title: Text('Sync enabled', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
              subtitle: Text(
                'Fulus works fully offline either way — this only controls whether '
                'your data also backs up to sync once you\'re online.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncTriggersProvider).syncNow();
      ref.invalidate(_syncDetailStatusProvider);
      if (context.mounted) showFulusSnackbar(context, message: 'Sync started.');
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't reach the server right now — this will keep retrying.");
      }
    }
  }

  Future<void> _setEnabled(BuildContext context, WidgetRef ref, bool value) async {
    await ref.read(syncConfigProvider).setEnabled(value);
    // syncConfigProvider itself is a fixed value from bootstrap.dart
    // (invalidating it is a no-op) — but SyncStatusNotifier.watch()
    // only checks SyncConfig.isEnabled at the moment a subscriber
    // (re-)subscribes, not reactively within an already-open stream.
    // Invalidating this forces that re-subscription, which is what
    // actually picks up the flip — and rebuilds this whole widget in
    // the process, which is what picks up the new isEnabled value
    // everywhere else on this screen (the Sync Now button, the switch
    // itself) in the same pass.
    ref.invalidate(_syncDetailStatusProvider);
    if (!context.mounted) return;
    showFulusSnackbar(
      context,
      message: value
          ? 'Sync enabled. Restart Fulus for this to take effect.'
          : 'Sync disabled. Data already queued will stay queued until you turn this back on.',
    );
  }
}

/// [syncStatusNotifierProvider] exposes a Stream; wrapped as a
/// StreamProvider here rather than watched with a raw StreamBuilder so
/// this screen can `ref.invalidate` it the same way it invalidates
/// everything else after Sync Now / the enable toggle.
final _syncDetailStatusProvider = StreamProvider.autoDispose<SyncStatus>((ref) {
  return ref.watch(syncStatusNotifierProvider).watch();
});

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.syncEnabled});
  final SyncStatus status;
  final bool syncEnabled;

  @override
  Widget build(BuildContext context) {
    final (icon, color, headline, body) = switch (status.kind) {
      SyncStatusKind.disabled => (
          Icons.cloud_off_outlined,
          AppColors.textSecondaryOf(context),
          'Sync is off',
          'Turn it on below to back your data up once you\'re online. Nothing here is required — Fulus works fully offline.',
        ),
      SyncStatusKind.settled => (
          Icons.cloud_done_outlined,
          AppColors.primaryOf(context),
          'Everything is synced',
          'All your data is backed up.',
        ),
      SyncStatusKind.pending => (
          Icons.cloud_upload_outlined,
          AppColors.textSecondaryOf(context),
          '${status.pendingCount} item${status.pendingCount == 1 ? '' : 's'} waiting to sync',
          'Nothing recorded is at risk — this will send the moment you\'re back online.',
        ),
      SyncStatusKind.syncing => (
          Icons.sync,
          AppColors.primaryOf(context),
          'Syncing now',
          '${status.pendingCount} item${status.pendingCount == 1 ? '' : 's'} being sent.',
        ),
      SyncStatusKind.attentionNeeded => (
          Icons.warning_amber_outlined,
          AppColors.warningOf(context),
          '${status.attentionCount} item${status.attentionCount == 1 ? '' : 's'} need attention',
          'These have failed to sync several times in a row. Your data is safe on this '
              'device — try Sync now, or check your connection.',
        ),
    };

    return FulusCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: AppIconSize.emphasis),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.xs),
                Text(body, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
