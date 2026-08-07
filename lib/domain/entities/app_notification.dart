import 'package:equatable/equatable.dart';

/// Stage 13 — Notifications.
///
/// Volume 12 Decision 43 is deliberately narrow: "notifications are
/// reserved for exactly two situations." This enum encodes that
/// narrowness directly in the type system rather than leaving it as
/// prose a future caller might not read — adding a third notification
/// type means editing this enum (and consciously updating this doc
/// comment's claim), not just calling a generic `notify(title, body)`
/// method with a new string somewhere.
///
/// Everything else this codebase might eventually want to surface as an
/// alert — low stock, a customer's credit crossing a limit, a pending
/// leave request — is deliberately NOT here. The desktop backend's own
/// notification_service.py generates exactly that broader set (see
/// HANDOVER-2.md's note on this), but Volume 12 Decision 43 considered
/// and rejected the "notify on everything" shape specifically for
/// mobile, in favor of a narrow, calm, always-actionable set. That
/// broader, rule-based, in-app-only feed maps onto Volume 10's
/// "Insights" instead (Reports, Stage 12 — not this stage) — a
/// genuinely different mechanism from an interruptive OS notification.
enum AppNotificationType {
  /// Volume 12: "pending data that's stayed unsynced for an unusually
  /// long time despite the device showing as online." Triggered by
  /// sync/sync_status_notifier.dart's checkForStuckSyncAndNotify.
  stuckSync,

  /// Volume 12: "a Card or Mobile Money payment that was blocked
  /// offline (Volume 5, Decision 17) finally completing once
  /// connectivity returns." Triggered by whichever future Sales/Payments
  /// code (Stage 7, not this stage) owns Card/Mobile Money retry —
  /// NotificationService.notifyBlockedPaymentCompleted exists as the
  /// hook that code calls into, not something this stage fabricates a
  /// caller for.
  blockedPaymentCompleted,
}

/// A record of one notification this device has shown — the in-app
/// history a future bell-icon/inbox surface reads from, since an OS
/// notification itself is ephemeral (dismissible, easy to miss, cleared
/// on reboot on some OEM skins). See data/local/database/tables.dart's
/// AppNotifications table for the persisted shape this mirrors.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.relatedEntityId,
  });

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  /// A related record's localId, when one exists — e.g. the Sale a
  /// blockedPaymentCompleted notification is about. Deliberately loose
  /// (a plain nullable String, not a typed reference) — see
  /// tables.dart's AppNotifications for why a real foreign key can't
  /// model "one of several possible entity types" cleanly. Null for
  /// stuckSync, which has no single related record.
  final String? relatedEntityId;

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      relatedEntityId: relatedEntityId,
    );
  }

  @override
  List<Object?> get props =>
      [id, type, title, body, createdAt, isRead, relatedEntityId];
}
