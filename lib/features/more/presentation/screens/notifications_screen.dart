import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/app_notification.dart';
import '../../../../shared/widgets/widgets.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(notificationRepositoryProvider);
    return FulusScreen(
      title: 'Notifications',
      subtitle: 'Important updates about your business',
      applyPadding: false,
      actions: [
        FulusIconButton(icon: FulusIcons.check, tooltip: 'Mark all read', onPressed: () => repo.markAllRead()),
      ],
      body: StreamBuilder<List<AppNotification>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load your notifications.",
              reassurance: 'Nothing has been deleted — this is only about showing the inbox right now.',
              onRetry: () => ref.invalidate(notificationRepositoryProvider),
            );
          }
          if (!snapshot.hasData) return const FulusLoadingIndicator();
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
                          _NotificationSummary(notifications: notifications),
                          const SizedBox(height: AppSpacing.lg),
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

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({required this.notifications});
  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final unread = notifications.where((notification) => !notification.isRead).length;
    return FulusCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.selectedTintOf(context), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(FulusIcons.notifications, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(unread == 0 ? 'All caught up' : '$unread unread ${unread == 1 ? 'notification' : 'notifications'}', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Text('${notifications.length} ${notifications.length == 1 ? 'update' : 'updates'} in your inbox', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ],
      ),
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
    return FulusActionTile(
      icon: isSync ? FulusIcons.sync : FulusIcons.check,
      label: notification.title,
      subtitle: notification.body,
      onTap: notification.isRead ? null : onRead,
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onRead});
  final AppNotification notification;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final isSync = notification.type == AppNotificationType.stuckSync;
    final color = notification.isRead ? AppColors.textSecondaryOf(context) : AppColors.primaryOf(context);
    return FulusListRow(
      leading: Icon(isSync ? FulusIcons.sync : FulusIcons.check, color: color),
      title: Text(notification.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w700)),
      subtitle: Text(notification.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      trailing: notification.isRead ? null : FulusIconButton(icon: FulusIcons.check, tooltip: 'Mark as read', onPressed: onRead),
      onTap: notification.isRead ? null : onRead,
    );
  }
}
