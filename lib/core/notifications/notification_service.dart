import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

/// The single entry point for showing an OS-level notification. Every
/// call also writes an [AppNotification] to [NotificationRepository].
/// Sync notifications are intentionally rare: only a persistent sync
/// problem is surfaced because normal offline operation is expected.
class NotificationService {
  NotificationService({
    required NotificationRepository notificationRepository,
    FlutterLocalNotificationsPlugin? plugin,
  })  : _notificationRepository = notificationRepository,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final NotificationRepository _notificationRepository;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _paymentChannel = AndroidNotificationChannel(
    'fulus_payment_completed',
    'Payment confirmations',
    description:
        'A Card or Mobile Money payment that was blocked offline has now gone through.',
    importance: Importance.high,
  );

  static const _syncChannel = AndroidNotificationChannel(
    'fulus_sync_attention',
    'Sync status',
    description: 'Your data needs a moment of attention to finish syncing.',
    importance: Importance.defaultImportance,
  );

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_paymentChannel);
    await androidPlugin?.createNotificationChannel(_syncChannel);

    _initialized = true;
  }

  Future<bool> ensurePermission() async {
    await initialize();
    return _ensurePermission();
  }

  Future<bool> _ensurePermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final granted = await androidPlugin.requestNotificationsPermission();
    return granted ?? false;
  }

  /// A persistent sync problem is a gentle heads-up, not an indication
  /// that local work was lost. Automatic retries continue in the
  /// background; the notification deliberately gives no technical action
  /// the owner needs to perform.
  Future<void> notifyStuckSync({required int attentionCount}) async {
    await initialize();
    if (!await _ensurePermission()) return;

    final title = 'Cloud backup is taking longer than usual';
    final body = attentionCount == 1
        ? 'Your work is safe on this device. Fulus will keep trying automatically.'
        : '$attentionCount items are taking longer than usual. Your work is safe on this device and Fulus will keep trying automatically.';

    await _show(
      channel: _syncChannel,
      title: title,
      body: body,
      type: AppNotificationType.stuckSync,
    );
  }

  Future<void> notifyBlockedPaymentCompleted({
    required String saleId,
    required String amountDisplay,
  }) async {
    await initialize();
    if (!await _ensurePermission()) return;

    await _show(
      channel: _paymentChannel,
      title: 'Payment confirmed',
      body: '$amountDisplay has now gone through.',
      type: AppNotificationType.blockedPaymentCompleted,
      relatedEntityId: saleId,
    );
  }

  Future<void> _show({
    required AndroidNotificationChannel channel,
    required String title,
    required String body,
    required AppNotificationType type,
    String? relatedEntityId,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.defaultPriority,
        ),
      ),
    );

    await _notificationRepository.record(
      AppNotification(
        id: Ulid().toString(),
        type: type,
        title: title,
        body: body,
        createdAt: DateTime.now(),
        isRead: false,
        relatedEntityId: relatedEntityId,
      ),
    );
  }
}
