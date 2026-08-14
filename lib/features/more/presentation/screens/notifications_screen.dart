import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../domain/entities/app_notification.dart';
import '../../../shared/widgets/widgets.dart';

/// Gap fix — full backend (NotificationRepository, NotificationService,
/// the `flutter_local_notifications` package itself) existed with no
/// screen anywhere reading it: confirmed by grep, zero references to
/// notificationRepositoryProvider/notificationServiceProvider inside
/// lib/features, no bell icon anywhere, no inbox screen.
///
/// Deliberately narrow, matching this app's own scope decision (see
/// AppNotificationType's header comment): only stuckSync and
/// blockedPaymentCompleted exist as notification types at all here.
/// This is that "future bell-icon/inbox screen" the repository's own
/// doc comment already anticipated, not a broader notification center.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(notificationRepositoryProvider);
    return FulusScreen(
      title: 'Notifications',
      applyPadding: false,
      actions: [
        FulusIconButton(
          icon: Icons.done_all,
          tooltip: 'Mark all read',
          onPressed: () => repo.markAllRead(),
        ),
      ],
      body: StreamBuilder<List<AppNotification>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const FulusLoadingIndicator();
          }
          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return FulusEmptyState(
              icon: Icons.notifications_none_outlined,
              headline: 'Nothing here.',
              body: 'Fulus only notifies you about a couple of specific things — sync '
                  'that\'s been stuck a while, and a blocked payment going through once '
                  'you\'re back online.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final notification = notifications[i];
              return FulusCard(
                onTap: notification.isRead ? null : () => repo.markRead(notification.id),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      notification.type == AppNotificationType.stuckSync
                          ? Icons.sync_problem_outlined
                          : Icons.check_circle_outline,
                      color: notification.isRead ? AppColors.textSecondaryOf(context) : AppColors.primaryOf(context),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(notification.body, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
