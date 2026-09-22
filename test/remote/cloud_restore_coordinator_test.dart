import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import '../../lib/data/local/database/database.dart';
import '../../lib/data/remote/cloud_restore_coordinator.dart';
import '../../lib/domain/entities/business_settings.dart';

void main() {
  late AppDatabase db;
  late CloudRestoreCoordinator coordinator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = CloudRestoreCoordinator(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('clears stale outbound sync work from the previous local installation', () async {
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'stale-queue-item',
        entityType: 'sale',
        entityLocalId: 'old-local-sale',
        operation: 'create',
        priority: 1,
        enqueuedAt: DateTime(2026, 9, 20),
      ),
    );
    expect(await db.select(db.syncQueueItems).get(), hasLength(1));

    const ownerId = 'owner-cloud-id';
    final snapshot = <String, dynamic>{
      'version': 6,
      'membership': {'user_id': ownerId, 'role_name': 'owner'},
      'profile': {'id': ownerId, 'full_name': 'Amina Yusuf'},
      'business_memberships': [
        {
          'id': 'membership-owner',
          'user_id': ownerId,
          'role_id': 'role-owner',
          'status': 'active',
          'created_at': '2026-09-13T00:00:00Z',
          'updated_at': '2026-09-13T00:00:00Z',
        },
      ],
      'roles': [
        {'id': 'role-owner', 'name': 'owner'},
      ],
      'permissions': [],
      'role_permissions': [],
      'location_memberships': [],
    };
    const settings = BusinessSettingsResponseDto(
      id: 'business-id',
      businessName: 'Amina Store',
      vatEnabled: false,
      vatRate: 0,
      currencySymbol: '₦',
      receiptFooter: 'Thank you',
    );

    await coordinator.restore(
      snapshot: snapshot,
      ownerCloudUserId: ownerId,
      ownerEmail: 'amina@example.com',
      settings: settings,
    );

    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });

  test('clears stale conflict records from the previous local dataset', () async {
    await db.into(db.syncConflictRecords).insert(
      SyncConflictRecordsCompanion.insert(
        id: 'stale-conflict',
        operationId: 'stale-operation',
        entityType: 'sale',
        entityLocalId: 'old-local-sale',
        code: 'SYNC_CONFLICT',
        message: 'Old local conflict',
        createdAt: DateTime(2026, 9, 20),
      ),
    );
    expect(await db.select(db.syncConflictRecords).get(), hasLength(1));

    const ownerId = 'owner-cloud-id';
    final snapshot = <String, dynamic>{
      'version': 6,
      'membership': {'user_id': ownerId, 'role_name': 'owner'},
      'profile': {'id': ownerId, 'full_name': 'Amina Yusuf'},
      'business_memberships': [
        {
          'id': 'membership-owner',
          'user_id': ownerId,
          'role_id': 'role-owner',
          'status': 'active',
          'created_at': '2026-09-13T00:00:00Z',
          'updated_at': '2026-09-13T00:00:00Z',
        },
      ],
      'roles': [
        {'id': 'role-owner', 'name': 'owner'},
      ],
      'permissions': [],
      'role_permissions': [],
      'location_memberships': [],
    };
    const settings = BusinessSettingsResponseDto(
      id: 'business-id',
      businessName: 'Amina Store',
      vatEnabled: false,
      vatRate: 0,
      currencySymbol: '₦',
      receiptFooter: 'Thank you',
    );

    await coordinator.restore(
      snapshot: snapshot,
      ownerCloudUserId: ownerId,
      ownerEmail: 'amina@example.com',
      settings: settings,
    );

    expect(await db.select(db.syncConflictRecords).get(), isEmpty);
  });

  test('restores owner identity, settings, and current session', () async {
    const ownerId = 'owner-cloud-id';
    final snapshot = <String, dynamic>{
      'version': 6,
      'membership': {'user_id': ownerId, 'role_name': 'owner'},
      'profile': {'id': ownerId, 'full_name': 'Amina Yusuf'},
      'business_memberships': [
        {
          'id': 'membership-owner',
          'user_id': ownerId,
          'role_id': 'role-owner',
          'status': 'active',
          'created_at': '2026-09-13T00:00:00Z',
          'updated_at': '2026-09-13T00:00:00Z',
        },
      ],
      'roles': [
        {'id': 'role-owner', 'name': 'owner'},
      ],
      'permissions': [],
      'role_permissions': [],
      'location_memberships': [],
    };
    const settings = BusinessSettingsResponseDto(
      id: 'business-id',
      businessName: 'Amina Store',
      vatEnabled: false,
      vatRate: 0,
      currencySymbol: '₦',
      receiptFooter: 'Thank you',
    );

    await coordinator.restore(
      snapshot: snapshot,
      ownerCloudUserId: ownerId,
      ownerEmail: 'amina@example.com',
      settings: settings,
    );

    final owner = await (db.select(db.users)
          ..where((u) => u.localId.equals(ownerId)))
        .getSingle();
    expect(owner.role.name, 'owner');
    expect(owner.fullName, 'Amina Yusuf');
    expect(owner.email, 'amina@example.com');

    final employees = await (db.select(db.employees)
          ..where((e) => e.authUserId.equals(ownerId)))
        .get();
    expect(employees, isEmpty);

    final session = await (db.select(db.sessions)
          ..where((s) => s.id.equals('current')))
        .getSingle();
    expect(session.userId, ownerId);

    final localSettings = await (db.select(db.businessSettings)).getSingle();
    expect(localSettings.businessName, 'Amina Store');
    expect(localSettings.currencySymbol, '₦');
  });

  test('does not upgrade a cloud administrator to the unrestricted owner role', () async {
    const adminId = 'admin-cloud-id';
    final snapshot = <String, dynamic>{
      'version': 6,
      'membership': {'user_id': adminId, 'role_name': 'admin'},
      'profile': {'id': adminId, 'full_name': 'Admin User'},
      'business_memberships': [
        {
          'id': 'membership-admin',
          'user_id': adminId,
          'role_id': 'role-admin',
          'status': 'active',
          'created_at': '2026-09-13T00:00:00Z',
          'updated_at': '2026-09-13T00:00:00Z',
        },
      ],
      'roles': [
        {'id': 'role-admin', 'name': 'admin'},
      ],
      'permissions': [],
      'role_permissions': [],
      'location_memberships': [],
    };
    const settings = BusinessSettingsResponseDto(
      id: 'business-id',
      businessName: 'Admin Store',
      vatEnabled: false,
      vatRate: 0,
      currencySymbol: '₦',
      receiptFooter: 'Thank you',
    );

    await coordinator.restore(
      snapshot: snapshot,
      ownerCloudUserId: adminId,
      ownerEmail: 'admin@example.com',
      settings: settings,
    );

    final admin = await (db.select(db.users)
          ..where((u) => u.localId.equals(adminId)))
        .getSingle();
    expect(admin.role.name, 'manager');
  });
}
