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

  test('restores owner identity, settings, and current session', () async {
    const ownerId = 'owner-cloud-id';
    final snapshot = <String, dynamic>{
      'version': 5,
      'membership': {'user_id': ownerId},
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
}
