import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../data/local/database/database.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../../sync/sync_status.dart';
import '../../../../../sync/sync_user_message.dart';

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
      await ref.read(syncQueueProvider).normalizeDependencyPriorities();
      await ref.read(syncTriggersProvider).syncNow();
      if (!mounted) return;
      ref.invalidate(_syncDetailStatusProvider);
      showFulusSnackbar(
        context,
        message: 'Backup checked. Fulus will keep trying automatically if anything is still waiting.',
      );
    } catch (_) {
      if (!mounted) return;
      showFulusSnackbar(
        context,
        message: 'Backup could not be completed yet. Your work is still safe on this device.',
      );
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(_syncDetailStatusProvider);
    final connection = ref.watch(fulusConnectionStateProvider);
    final selectedBusinessId = connection.selectedBusinessId;
    final health = selectedBusinessId == null
        ? const SyncHealthSnapshot()
        : ref.read(syncStatusNotifierProvider).healthFor(selectedBusinessId);
    return FulusScreen(
      title: 'Sync & backup',
      subtitle: 'See what is backed up and what Fulus is still working on',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final inset = wide ? AppSpacing.lg : AppSpacing.xs;
          return ListView(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FulusSectionHeader(
                        title: 'Your data',
                        subtitle: 'Fulus saves locally first, then backs up when Cloud is connected',
                      ),
                      statusAsync.when(
                        data: (status) => _StatusCard(
                          status: status.kind == SyncStatusKind.disabled || connection.isSyncReady
                              ? status
                              : const SyncStatus.cloudUnavailable(),
                          syncingNow: _syncingNow,
                          onSyncNow: status.kind == SyncStatusKind.disabled ? null : _syncNow,
                        ),
                        loading: () => const FulusLoadingIndicator(),
                        error: (_, __) => FulusErrorState(
                          message: "Couldn't read backup status.",
                          reassurance: 'Your local business data is not affected by this status check.',
                          onRetry: () => ref.invalidate(_syncDetailStatusProvider),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _HealthCard(health: health),
                      const SizedBox(height: AppSpacing.lg),
                      const _ConflictCard(),
                      const SizedBox(height: AppSpacing.lg),
                      const FulusSectionHeader(
                        title: 'How Fulus protects your work',
                        subtitle: 'Cloud backup never replaces your local-first workflow',
                      ),
                      FulusCard(
                        child: Column(
                          children: [
                            _InfoRow(
                              icon: Icons.phone_android_outlined,
                              title: 'Saved on this device first',
                              body: 'Sales, stock, customers, and other business work remain available locally.',
                            ),
                            const FulusListDivider(),
                            _InfoRow(
                              icon: Icons.cloud_outlined,
                              title: 'Backed up when connected',
                              body: 'Fulus Cloud sends pending changes automatically when the connection is available.',
                            ),
                            const FulusListDivider(),
                            _InfoRow(
                              icon: Icons.sync_outlined,
                              title: 'Safe to keep working offline',
                              body: 'A delayed backup does not block normal business operations on this device.',
                            ),
                          ],
                        ),
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
}

final _syncDetailStatusProvider = StreamProvider.autoDispose<SyncStatus>((ref) {
  return ref.watch(syncStatusNotifierProvider).watch();
});

final _unresolvedConflictsProvider =
    StreamProvider.autoDispose<List<SyncConflictRecord>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncConflictRecords)
        ..where((c) => c.resolvedAt.isNull())
        ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
      .watch();
});

class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard();

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  String? _resolvingId;

  Future<void> _keepLocal(SyncConflictRecord conflict) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = conflict.id);
    try {
      await ref.read(syncConflictResolverProvider).keepLocalVersion(conflict.id);
      await ref.read(syncTriggersProvider).syncNow();
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Your local version was sent back to Cloud.');
      ref.invalidate(_syncDetailStatusProvider);
    } catch (_) {
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Fulus could not send your local version yet. It remains safe on this device.');
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  Future<void> _keepCloud(SyncConflictRecord conflict) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = conflict.id);
    try {
      await ref.read(syncConflictResolverProvider).keepCloudVersion(conflict.id);
      if (!mounted) return;
      showFulusSnackbar(
        context,
        message: 'The cloud version is now saved on this device.',
      );
      ref.invalidate(_syncDetailStatusProvider);
    } catch (_) {
      if (!mounted) return;
      showFulusSnackbar(
        context,
        message: 'Fulus could not refresh this change yet. Your local data is still safe.',
      );
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflictsAsync = ref.watch(_unresolvedConflictsProvider);
    return conflictsAsync.when(
      data: (conflicts) {
        if (conflicts.isEmpty) return const SizedBox.shrink();
        return FulusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Changes need review',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Another device changed the same data. You can accept the current Cloud version to clear the local conflict.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...conflicts.map(
                (conflict) => Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          syncEntityLabel(conflict.entityType),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimaryOf(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Another device changed this ${syncEntityLabel(conflict.entityType)}. Choose which version to keep.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            FulusButton(
                              label: _resolvingId == conflict.id
                                  ? 'Working…'
                                  : 'Use Cloud version',
                              loading: _resolvingId == conflict.id,
                              onPressed: _resolvingId == null
                                  ? () => _keepCloud(conflict)
                                  : null,
                              variant: FulusButtonVariant.secondary,
                            ),
                            FulusButton(
                              label: 'Keep my version',
                              loading: false,
                              onPressed: _resolvingId == null
                                  ? () => _keepLocal(conflict)
                                  : null,
                              variant: FulusButtonVariant.secondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.syncingNow, required this.onSyncNow});

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
      SyncStatusKind.cloudUnavailable => (
          Icons.cloud_off_outlined,
          AppColors.textSecondaryOf(context),
          'Cloud backup is reconnecting',
          'Your work is safe on this device. Fulus will resume backup automatically when Cloud is ready.',
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

    final settled = status.kind == SyncStatusKind.settled;
    final displayBody = status.conflictCount > 0
        ? '${status.conflictCount} change${status.conflictCount == 1 ? '' : 's'} need review because another device changed the same data.'
        : body;
    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            headline,
            style: AppTypography.heading.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            displayBody,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          if (onSyncNow != null && !settled && status.conflictCount == 0) ...[
            const SizedBox(height: AppSpacing.lg),
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

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final SyncHealthSnapshot health;

  String _when(DateTime? value) {
    if (value == null) return 'Not yet recorded';
    return value.toLocal().toString().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cloud health',
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _HealthLine(label: 'Last successful backup', value: _when(health.lastPushAt)),
          const FulusListDivider(),
          _HealthLine(label: 'Last successful pull', value: _when(health.lastPullAt)),
          const FulusListDivider(),
          _HealthLine(
            label: 'Cloud backup',
            value: health.recoveryState == 'recovering'
                ? 'Restoring'
                : health.recoveryState == 'blocked'
                    ? 'Temporarily unavailable'
                    : health.lastPushAt != null && health.lastPullAt != null
                        ? 'Up to date'
                        : 'Waiting for first backup',
          ),
        ],
      ),
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
        Text(
          value,
          style: AppTypography.caption.copyWith(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.selectedTintOf(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: AppColors.primaryOf(context)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
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
    );
  }
}
