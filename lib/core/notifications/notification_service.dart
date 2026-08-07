import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

/// Stage 13 — Notifications.
///
/// The single entry point for showing an OS-level notification. Every
/// call also writes an [AppNotification] to [NotificationRepository] —
/// callers get both the interruptive OS notification AND the
/// non-interruptive in-app history entry from one call, rather than
/// needing to remember to do both themselves (the same "one call, the
/// obvious side effect happens too" shape AuthRepositoryImpl's
/// _persistSession already uses internally for sessions).
///
/// Deliberately exposes exactly two public methods —
/// [notifyStuckSync] and [notifyBlockedPaymentCompleted] — matching
/// Volume 12 Decision 43's own "exactly two situations" precisely,
/// rather than a generic `notify(title, body)` a future caller could
/// use to reintroduce the "notify on everything" pattern Decision 43
/// deliberately rejected. Adding a third real situation later means
/// adding a third named method here (and a third AppNotificationType),
/// a conscious, visible change — not a new call site quietly reusing a
/// generic one.
class NotificationService {
  NotificationService({
    required NotificationRepository notificationRepository,
    FlutterLocalNotificationsPlugin? plugin,
  })  : _notificationRepository = notificationRepository,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final NotificationRepository _notificationRepository;
  final FlutterLocalNotificationsPlugin _plugin;

  /// Two channels, not one — Android's own notification-settings screen
  /// lets an owner control each channel independently, and these two
  /// situations genuinely differ in urgency (a completed payment is good
  /// news worth a sound; a stuck sync is a "when you get a chance" nudge,
  /// not urgent enough to disturb someone the same way — Volume 12's own
  /// "gentle nudge" phrasing for this one specifically). Splitting them
  /// gives an owner who wants payment confirmations but not sync nudges
  /// (or vice versa) a real, standard OS-level way to say so, rather
  /// than an all-or-nothing app-level toggle this stage would have to
  /// build itself.
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

  /// Idempotent, and deliberately NOT called from bootstrap.dart —
  /// unlike SyncTriggers.start() or similar one-time setup, channel
  /// creation has no reason to happen before this service is first
  /// actually used. [notifyStuckSync] and
  /// [notifyBlockedPaymentCompleted] both call this themselves as their
  /// first line, so bootstrap.dart doesn't need to (and requesting the
  /// POST_NOTIFICATIONS runtime permission — [_ensurePermission] — is
  /// kept separate from this method entirely, for the contextual-timing
  /// reason explained on that method).
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

  Future<bool> _ensurePermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final granted = await androidPlugin.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Volume 12: "pending data that's stayed unsynced for an unusually
  /// long time despite the device showing as online." Called from
  /// sync/sync_status_notifier.dart, which already owns the "has this
  /// actually been stuck long enough, and have I already said so once"
  /// judgment — this method's only job is showing it and logging it.
  Future<void> notifyStuckSync({required int attentionCount}) async {
    await initialize();
    if (!await _ensurePermission()) return;

    final title = 'Sync needs a moment';
    final body = attentionCount == 1
        ? "1 item hasn't synced yet — check your connection, or try Sync Now."
        : "$attentionCount items haven't synced yet — check your connection, or try Sync Now.";

    await _show(
      channel: _syncChannel,
      title: title,
      body: body,
      type: AppNotificationType.stuckSync,
    );
  }

  /// Volume 12: "a Card or Mobile Money payment that was blocked offline
  /// (Volume 5, Decision 17) finally completing once connectivity
  /// returns." [saleId] is the local Sale this payment belongs to —
  /// intentionally the only entity-specific parameter, with the
  /// caller (future Sales/Payments retry logic, Stage 7 — not this
  /// stage) responsible for its own amount/currency formatting rather
  /// than this service reaching into BusinessSettingsRepository itself
  /// to guess at it.
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
