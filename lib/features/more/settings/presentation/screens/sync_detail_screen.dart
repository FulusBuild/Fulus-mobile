import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../../sync/sync_status.dart';

/// A simple, human-readable view of automatic cloud backup.
///
/// Sync is intentionally not presented as a feature the owner needs to
/// operate. Fulus saves locally first and handles cloud synchronization in
/// the background whenever Cloud is connected and the device is online.
class SyncDetailScreen extends ConsumerStatefulWidget {
  const SyncDetailScreen({super.key});

  @override
  ConsumerState<SyncDetailScreen> createState() => _SyncDetailScreenState();
}

class _SyncDetailScreenState extends ConsumerState<SyncDetailScreen> {
  bool _syncingNow = false;

  Future<void> _syncNow() async {
    if (_syncingNow) return;
    setState(() => _syncingNow = true);
    try {
      await ref.read(syncTriggersProvider).syncNow();
      if (!mounted) return;
      ref.invalidate(_syncDetailStatusProvider);
      showFulusSnackbar(context, message: 'Backup checked. Fulus will keep trying automatically if anything is still waiting.');
    } catch (error) {
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Backup could not be completed yet. Your work is still safe on this device.');
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(_syncDetailStatusProvider);

    return FulusScreen(
      title: 'Sync & backup',
      body: ListView(
        children: [
          FulusSectionHeader(title: 'Your data'),
          statusAsync.when(
            data: (status) => _StatusCard(
              status: status,
              syncingNow: _syncingNow,
              onSyncNow: status.kind == SyncStatusKind.disabled ? null : _syncNow,
            ),
            loading: () => const FulusLoadingIndicator(),
            error: (_, __) => FulusErrorState(
              message: "Couldn't read backup status.",
              onRetry: () => ref.invalidate(_syncDetailStatusProvider),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.textSecondaryOf(context),
                  size: AppIconSize.compact,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Fulus always saves your work on this device first. When Fulus Cloud is connected, backup and sync happen automatically in the background.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _syncDetailStatusProvider = StreamProvider.autoDispose<SyncStatus>((ref) {
  return ref.watch(syncStatusNotifierProvider).watch();
});

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.syncingNow,
    required this.onSyncNow,
  });

  final SyncStatus status;
  final bool syncingNow;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final (icon, color, headline, body) = switch (status.kind) {
      SyncStatusKind.disabled => (
          Icons.cloud_off_outlined,
          AppColors.textSecondaryOf(context),
          'Cloud backup is off',
          'Your work is still safe on this device. Connect Fulus Cloud to back it up and use it across devices.',
        ),
      SyncStatusKind.settled => (
          Icons.cloud_done_outlined,
          AppColors.primaryOf(context),
          'Everything is backed up',
          'Nothing needs your attention.',
        ),
      SyncStatusKind.pending => (
          Icons.cloud_upload_outlined,
          AppColors.textSecondaryOf(context),
          'Backup will continue automatically',
          'Your work is safe on this device and will be sent when a connection is available.',
        ),
      SyncStatusKind.syncing => (
          Icons.sync,
          AppColors.primaryOf(context),
          'Backing up now',
          'Fulus is sending your saved work in the background.',
        ),
      SyncStatusKind.attentionNeeded => (
          Icons.warning_amber_outlined,
          AppColors.warningOf(context),
          'Some backup is taking longer than usual',
          'Your work is safe on this device. Fulus will keep trying automatically. If this continues, check your internet connection.',
        ),
    };

    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: AppIconSize.emphasis),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: AppTypography.subheading.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onSyncNow != null && status.kind != SyncStatusKind.settled) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: syncingNow ? 'Checking backup…' : 'Try backup now',
                loading: syncingNow,
                onPressed: syncingNow ? null : onSyncNow,
                variant: FulusButtonVariant.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
