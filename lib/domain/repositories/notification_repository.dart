import '../entities/app_notification.dart';

/// Architecture Section 4's repository pattern, applied to Stage 13's
/// in-app notification history. Purely local (see
/// data/local/database/tables.dart's AppNotifications doc comment on why
/// this is deliberately not a SyncableColumns table) — every method here
/// is local-only, with no server-reconciliation counterpart the way
/// markSynced exists on the syncable repositories.
abstract class NotificationRepository {
  /// Called by NotificationService (core/notifications/) immediately
  /// after showing an OS notification — this is the log entry, not a
  /// second independent write path a caller could get out of sync with
  /// the OS notification itself.
  Future<void> record(AppNotification notification);

  /// Reactive, newest-first — a future bell-icon/inbox screen's natural
  /// data source.
  Stream<List<AppNotification>> watchAll();

  Future<int> unreadCount();

  Future<void> markRead(String id);

  Future<void> markAllRead();
}
