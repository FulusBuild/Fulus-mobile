import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/async_timeout.dart';
import '../../../../domain/entities/app_notification.dart';
import '../../../../shared/widgets/widgets.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(notificationRepositoryProvider);
    return FulusScreen(
      title: 'Notifications',
      applyPadding: false,
      actions: [
        FulusIconButton(icon: FulusIcons.check, tooltip: 'Mark all read', onPressed: () => repo.markAllRead()),
      ],
      body: StreamBuilder<List<AppNotification>>(
        stream: repo.watchAll().withFulusLoadingTimeout(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load your notifications.",
              reassurance: 'Nothing has been deleted — this is only about showing the inbox right now.',
              onRetry: () => ref.invalidate(notificationRepositoryProvider),
            );
          }
          if (!snapshot.hasData) return const _NotificationsSkeleton();
          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return const FulusEmptyState(
              icon: FulusIcons.notifications,
              headline: 'Nothing here.',
              body: 'Fulus will notify you when a supported sync or payment event needs your attention.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final notification in notifications)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _NotificationTile(
                                notification: notification,
                                onRead: () => repo.markRead(notification.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}


class _NotificationSummaryIcon extends StatelessWidget {
  const _NotificationSummaryIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.selectedTintOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(FulusIcons.notifications, color: AppColors.primaryOf(context)),
    );
  }
}
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onRead});

  final AppNotification notification;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final isSync = notification.type == AppNotificationType.stuckSync;
    return FulusListRow(
      leading: Icon(isSync ? FulusIcons.sync : FulusIcons.check),
      title: Text(notification.title),
      subtitle: Text(notification.body),
      trailing: notification.isRead ? null : const Icon(Icons.circle, size: 8),
      onTap: notification.isRead ? null : onRead,
    );
  }
}



class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
      children: const [
        FulusCardSkeleton(),
        SizedBox(height: AppSpacing.lg),
        FulusListRowSkeleton(hasLeading: true),
        FulusListRowSkeleton(hasLeading: true),
        FulusListRowSkeleton(hasLeading: true),
        FulusListRowSkeleton(hasLeading: true),
      ],
    );
  }
}
