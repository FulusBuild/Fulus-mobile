import 'package:drift/drift.dart';

import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';
import '../local/database/database.dart';
import 'notification_mapper.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> record(AppNotification notification) async {
    await _db.into(_db.appNotifications).insert(
          notification.toDriftCompanion(),
        );
  }

  @override
  Stream<List<AppNotification>> watchAll() {
    final query = _db.select(_db.appNotifications)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<int> unreadCount() async {
    final query = _db.select(_db.appNotifications)
      ..where((t) => t.isRead.equals(false));
    final rows = await query.get();
    return rows.length;
  }

  @override
  Future<void> markRead(String id) async {
    await (_db.update(_db.appNotifications)..where((t) => t.id.equals(id)))
        .write(AppNotificationsCompanion(isRead: Value(true)));
  }

  @override
  Future<void> markAllRead() async {
    await (_db.update(_db.appNotifications)..where((t) => t.isRead.equals(false)))
        .write(AppNotificationsCompanion(isRead: Value(true)));
  }
}
