import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/errors/failure.dart';
import '../../lib/data/local/database/database.dart';
import '../../lib/data/repositories/permission_repository_impl.dart';
import '../../lib/domain/entities/auth_user.dart';
import '../../lib/domain/entities/permission.dart';

Future<void> _insertUser(
  AppDatabase db, {
  required String id,
  required String name,
  required AuthRole role,
}) async {
  final now = DateTime.now();
  await db.into(db.users).insert(
        UsersCompanion.insert(
          localId: id,
          fullName: name,
          role: role,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late AppDatabase db;
  late PermissionRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = PermissionRepositoryImpl(db: db);
  });

  tearDown(() => db.close());

  test('owner can replace any employee grant', () async {
    await _insertUser(db, id: 'owner', name: 'Owner', role: AuthRole.owner);
    await _insertUser(db, id: 'employee', name: 'Employee', role: AuthRole.employee);

    await repository.setPermissions(
      userId: 'employee',
      permissions: {Permission.manageBackup, Permission.viewReports},
      grantedBy: 'owner',
    );

    expect(
      await repository.getPermissions('employee'),
      {Permission.manageBackup, Permission.viewReports},
    );
  });

  test('manager cannot add a permission they do not hold', () async {
    await _insertUser(db, id: 'owner', name: 'Owner', role: AuthRole.owner);
    await _insertUser(db, id: 'manager', name: 'Manager', role: AuthRole.manager);
    await repository.setPermissions(
      userId: 'manager',
      permissions: {Permission.manageEmployees, Permission.viewReports, Permission.manageStock},
      grantedBy: 'owner',
    );
    await _insertUser(db, id: 'employee', name: 'Employee', role: AuthRole.employee);

    await expectLater(
      repository.setPermissions(
        userId: 'employee',
        permissions: {Permission.manageBackup},
        grantedBy: 'manager',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('manager may preserve a target permission they do not hold', () async {
    await _insertUser(db, id: 'owner', name: 'Owner', role: AuthRole.owner);
    await _insertUser(db, id: 'manager', name: 'Manager', role: AuthRole.manager);
    await repository.setPermissions(
      userId: 'manager',
      permissions: {Permission.manageEmployees, Permission.viewReports, Permission.manageStock},
      grantedBy: 'owner',
    );
    await _insertUser(db, id: 'employee', name: 'Employee', role: AuthRole.employee);
    await repository.setPermissions(
      userId: 'employee',
      permissions: {Permission.manageBackup, Permission.manageStock},
      grantedBy: 'owner',
    );

    // The manager cannot grant manageBackup, but preserving an existing
    // manageBackup grant is allowed because it is not a change by this actor.
    await repository.setPermissions(
      userId: 'employee',
      permissions: {Permission.manageBackup, Permission.viewReports},
      grantedBy: 'manager',
    );

    expect(
      await repository.getPermissions('employee'),
      {Permission.manageBackup, Permission.viewReports},
    );
  });

  test('manager cannot edit their own permissions', () async {
    await _insertUser(db, id: 'owner', name: 'Owner', role: AuthRole.owner);
    await _insertUser(db, id: 'manager', name: 'Manager', role: AuthRole.manager);
    await repository.setPermissions(
      userId: 'manager',
      permissions: {Permission.manageEmployees, Permission.viewReports, Permission.manageStock},
      grantedBy: 'owner',
    );
    await expectLater(
      repository.setPermissions(
        userId: 'manager',
        permissions: const {},
        grantedBy: 'manager',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('a user without manageEmployees cannot change another user', () async {
    await _insertUser(db, id: 'employee', name: 'Employee', role: AuthRole.employee);
    await _insertUser(db, id: 'target', name: 'Target', role: AuthRole.employee);

    await expectLater(
      repository.setPermissions(
        userId: 'target',
        permissions: {Permission.viewReports},
        grantedBy: 'employee',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });
}
