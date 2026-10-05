import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/employee_identity_projection_store.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';

void main() {
  late AppDatabase db;
  late LocalEmployeeIdentityStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = LocalEmployeeIdentityStore(db);
  });

  tearDown(() => db.close());

  test('projects cloud staff identity, permissions, and session atomically', () async {
    await store.project(
      userId: 'cloud-user-1', membershipId: 'membership-1', roleName: 'cashier',
      fullName: 'Ada Lovelace', email: 'ada@example.test', locationId: null,
      permissionCodes: const ['sales.read', 'catalog.manage', 'reports.read'], employeeId: 'employee-1',
      employee: const {'full_name': 'Ada Lovelace', 'role': 'cashier', 'department': 'Sales', 'position': 'Cashier', 'salary': 250000, 'phone': '+10000000000', 'email': 'ada@example.test'},
    );
    final user = (await db.select(db.users).get()).single;
    expect(user.localId, 'cloud-user-1'); expect(user.email, 'ada@example.test'); expect(user.role, AuthRole.cashier); expect(user.isActive, isTrue);
    final employee = (await db.select(db.employees).get()).single;
    expect(employee.localId, 'employee-1'); expect(employee.serverId, 'employee-1'); expect(employee.membershipId, 'membership-1'); expect(employee.cloudUserId, 'cloud-user-1'); expect(employee.authUserId, 'cloud-user-1'); expect(employee.locationId, isNull); expect(employee.isActive, isTrue);
    final permissions = await db.select(db.userPermissions).get();
    expect(permissions.map((row) => row.permission).toSet(), {'viewMoney', 'manageStock', 'viewReports'});
    final session = (await db.select(db.sessions).get()).single;
    expect(session.id, 'current'); expect(session.userId, 'cloud-user-1'); expect(session.activeLocationId, isNull);
  });

  test('resolves an existing local employee by cloud identity before creating a duplicate', () async {
    await db.into(db.users).insert(UsersCompanion.insert(localId: 'cloud-user-2', username: const Value('employee'), fullName: 'Existing', role: AuthRole.employee, createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)));
    await db.into(db.employees).insert(EmployeesCompanion.insert(localId: 'local-employee', cloudUserId: const Value('cloud-user-2'), fullName: 'Existing', createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)));
    await store.project(userId: 'cloud-user-2', membershipId: 'membership-2', roleName: 'manager', fullName: 'Existing Updated', email: 'existing@example.test', locationId: null, permissionCodes: const [], employeeId: null, employee: const {});
    final rows = await db.select(db.employees).get();
    expect(rows.length, 1); expect(rows.single.localId, 'local-employee'); expect(rows.single.membershipId, 'membership-2'); expect(rows.single.authUserId, 'cloud-user-2');
  });

  test('revocation deactivates user and employee and clears access/session projection', () async {
    await store.project(userId: 'cloud-user-3', membershipId: 'membership-3', roleName: 'cashier', fullName: 'Revoked User', email: 'revoked@example.test', locationId: null, permissionCodes: const ['sales.read'], employeeId: 'employee-3', employee: const {});
    final revokedAt = DateTime(2026, 2, 1);
    await store.revoke(userId: 'cloud-user-3', revokedAt: revokedAt);
    final user = (await db.select(db.users).get()).single;
    expect(user.isActive, isFalse);
    final employee = (await db.select(db.employees).get()).single;
    expect(employee.isActive, isFalse); expect(employee.deletedAt, revokedAt);
    expect(await db.select(db.userPermissions).get(), isEmpty); expect(await db.select(db.sessions).get(), isEmpty);
  });
}
