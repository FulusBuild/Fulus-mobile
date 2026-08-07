import 'package:drift/drift.dart';

import '../../domain/entities/app_notification.dart';
import '../local/database/database.dart';

extension AppNotificationToCompanion on AppNotification {
  AppNotificationsCompanion toDriftCompanion() {
    return AppNotificationsCompanion.insert(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: Value(isRead),
      relatedEntityId: Value(relatedEntityId),
    );
  }
}

extension AppNotificationRowToDomain on AppNotificationRow {
  AppNotification toDomain() {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead,
      relatedEntityId: relatedEntityId,
    );
  }
}
