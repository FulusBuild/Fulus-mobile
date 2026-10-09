import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/employee_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/employee.dart';
import 'package:fulus_mobile/domain/entities/permission.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/domain/repositories/permission_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}
class _MockPermissionRepository extends Mock implements PermissionRepository {}

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late EmployeeRepositoryImpl repository;
  late _MockAuthRepository authRepository;
  late _MockPermissionRepository permissionRepository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.batch((batch) {
      batch.insertAll(db.locations, [
        LocationsCompanion.insert(
          localId: 'location-local-1',
          serverId: const Value('location-1'),
          name: 'Location 1',
          createdAt: DateTime.utc(2026, 9, 30, 10),
          updatedAt: DateTime.utc(2026, 9, 30, 10),
          syncStatus: SyncStatus.settled,
        ),
        LocationsCompanion.insert(
          localId: 'location-local-2',
          serverId: const Value('location-2'),
          name: 'Location 2',
          createdAt: DateTime.utc(2026, 9, 30, 10),
          updatedAt: DateTime.utc(2026, 9, 30, 10),
          syncStatus: SyncStatus.settled,
        ),
      ]);
    });
    syncQueue = SyncQueue(db);
    authRepository = _MockAuthRepository();
    permissionRepository = _MockPermissionRepository();
    repository = EmployeeRepositoryImpl(
      db: db,
      authRepository: authRepository,
      permissionRepository: permissionRepository,
      syncQueue: syncQueue,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('employee creation fails closed without an active session', () async {
    when(() => authRepository.currentUser).thenReturn(const AuthUser(
      id: 'owner-user',
      fullName: 'Owner',
      role: AuthRole.owner,
      isActive: true,
      hasLoginPin: false,
    ));
    when(() => permissionRepository.hasPermission(
      userId: 'owner-user',
      role: AuthRole.owner,
      permission: Permission.manageEmployees,
    )).thenAnswer((_) async => true);

    await expectLater(
      repository.createEmployee(const EmployeeDraft(
        fullName: 'Unscoped Employee',
        locationId: 'location-1',
      )),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.employees).get(), isEmpty);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });

  test('employee roster reads are isolated to the active location while sync can drain other-location outbox rows', () async {
    final now = DateTime.utc(2026, 10, 9, 10);
    await db.into(db.users).insert(
      UsersCompanion.insert(
        localId: 'owner-user',
        fullName: 'Owner',
        role: AuthRole.owner,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.batch((batch) {
      batch.insertAll(db.locations, [
        LocationsCompanion.insert(
          localId: 'location-a',
          name: 'Location A',
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ),
        LocationsCompanion.insert(
          localId: 'location-b',
          name: 'Location B',
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ),
      ]);
    });
    await db.into(db.sessions).insert(
      SessionsCompanion.insert(
        id: 'current',
        userId: 'owner-user',
        activeLocationId: const Value('location-a'),
      ),
    );
    for (final entry in [
      ('employee-a', 'Location A employee', 'location-a'),
      ('employee-b', 'Location B employee', 'location-b'),
    ]) {
      await db.into(db.employees).insert(
        EmployeesCompanion.insert(
          localId: entry.$1,
          fullName: entry.$2,
          locationId: Value(entry.$3),
          createdAt: now,
          updatedAt: now,
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
    }

    final visible = await repository.watchEmployees(isActive: true).first;
    expect(visible.map((employee) => employee.id), ['employee-a']);
    expect(await repository.getEmployeeById('employee-b'), isNull);
    expect(
      (await repository.getEmployeeById('employee-b', forSync: true))?.id,
      'employee-b',
    );
  });

  test('reconcileServerState creates a local projection with stable server identity', () async {
    final createdAt = DateTime.utc(2026, 9, 30, 10);
    final updatedAt = DateTime.utc(2026, 9, 30, 11);

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      membershipId: 'membership-1',
      cloudUserId: 'cloud-user-1',
      fullName: 'Amina Yusuf',
      role: 'Cashier',
      department: 'Sales',
      position: 'Cashier',
      salary: 85000,
      phone: '+2348000000001',
      email: 'amina@example.com',
      dateHired: DateTime.utc(2026, 1, 2),
      locationId: 'location-1',
      isActive: true,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );

    final rows = await db.select(db.employees).get();

    expect(rows, hasLength(1));
    expect(rows.single.serverId, 'employee-server-1');
    expect(rows.single.membershipId, 'membership-1');
    expect(rows.single.cloudUserId, 'cloud-user-1');
    expect(rows.single.fullName, 'Amina Yusuf');
    expect(rows.single.syncStatus, SyncStatus.settled);
    expect(rows.single.locationId, 'location-local-1');
  });

  test('reconcileServerState projects authoritative activation to the linked local login', () async {
    final now = DateTime.utc(2026, 9, 30, 10);
    await db.into(db.users).insert(
      UsersCompanion.insert(
        localId: 'cloud-user-1',
        fullName: 'Amina Yusuf',
        role: AuthRole.cashier,
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      membershipId: 'membership-1',
      cloudUserId: 'cloud-user-1',
      fullName: 'Amina Yusuf',
      role: 'Cashier',
      department: null,
      position: null,
      salary: null,
      phone: null,
      email: 'amina@example.com',
      dateHired: null,
      locationId: null,
      isActive: false,
      updatedAt: DateTime.utc(2026, 9, 30, 11),
      createdAt: now,
    );

    var user = await (db.select(db.users)..where((u) => u.localId.equals('cloud-user-1'))).getSingle();
    expect(user.isActive, isFalse);

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      membershipId: 'membership-1',
      cloudUserId: 'cloud-user-1',
      fullName: 'Amina Yusuf',
      role: 'Cashier',
      department: null,
      position: null,
      salary: null,
      phone: null,
      email: 'amina@example.com',
      dateHired: null,
      locationId: null,
      isActive: true,
      updatedAt: DateTime.utc(2026, 9, 30, 12),
      createdAt: now,
    );

    user = await (db.select(db.users)..where((u) => u.localId.equals('cloud-user-1'))).getSingle();
    expect(user.isActive, isTrue);
  });

  test('reconcileServerState updates the same local row instead of duplicating it', () async {
    final createdAt = DateTime.utc(2026, 9, 30, 10);
    final firstUpdatedAt = DateTime.utc(2026, 9, 30, 11);
    final secondUpdatedAt = DateTime.utc(2026, 9, 30, 12);

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      membershipId: 'membership-1',
      cloudUserId: 'cloud-user-1',
      fullName: 'Amina Yusuf',
      role: 'Cashier',
      department: null,
      position: null,
      salary: 85000,
      phone: null,
      email: 'amina@example.com',
      dateHired: null,
      locationId: 'location-1',
      isActive: true,
      updatedAt: firstUpdatedAt,
      createdAt: createdAt,
    );

    final first = (await db.select(db.employees).get()).single;

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      membershipId: 'membership-2',
      cloudUserId: 'cloud-user-2',
      fullName: 'Amina Ibrahim',
      role: 'Manager',
      department: 'Operations',
      position: 'Store Manager',
      salary: 120000,
      phone: '+2348000000002',
      email: 'amina.ibrahim@example.com',
      dateHired: DateTime.utc(2026, 2, 3),
      locationId: 'location-2',
      isActive: false,
      updatedAt: secondUpdatedAt,
      createdAt: createdAt,
    );

    final rows = await db.select(db.employees).get();

    expect(rows, hasLength(1));
    expect(rows.single.localId, first.localId);
    expect(rows.single.serverId, 'employee-server-1');
    expect(rows.single.membershipId, 'membership-2');
    expect(rows.single.cloudUserId, 'cloud-user-2');
    expect(rows.single.fullName, 'Amina Ibrahim');
    expect(rows.single.isActive, isFalse);
    expect(rows.single.deletedAt, DateTime(2026, 9, 30, 12));
    expect(rows.single.syncStatus, SyncStatus.settled);
  });

  test('reconcileServerState matches a local pending employee by client reference', () async {
    await db.into(db.employees).insert(
      EmployeesCompanion.insert(
        localId: 'employee-local-1',
        fullName: 'Pending employee',
        createdAt: DateTime.utc(2026, 9, 30, 10),
        updatedAt: DateTime.utc(2026, 9, 30, 10),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );

    await repository.reconcileServerState(
      serverId: 'employee-server-1',
      clientReference: 'employee-local-1',
      membershipId: null,
      cloudUserId: null,
      fullName: 'Pending employee',
      role: 'Cashier',
      department: null,
      position: null,
      salary: null,
      phone: null,
      email: 'pending@example.com',
      dateHired: null,
      locationId: null,
      isActive: true,
      updatedAt: DateTime.utc(2026, 9, 30, 11),
      createdAt: DateTime.utc(2026, 9, 30, 10),
    );

    final rows = await db.select(db.employees).get();

    expect(rows, hasLength(1));
    expect(rows.single.localId, 'employee-local-1');
    expect(rows.single.serverId, 'employee-server-1');
    expect(rows.single.email, 'pending@example.com');
    expect(rows.single.syncStatus, SyncStatus.settled);
  });

  test('markSynced records the cloud identity and settles the local employee', () async {
    await db.into(db.employees).insert(
      EmployeesCompanion.insert(
        localId: 'employee-local-1',
        fullName: 'Amina Yusuf',
        createdAt: DateTime.utc(2026, 9, 30, 10),
        updatedAt: DateTime.utc(2026, 9, 30, 10),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );

    await repository.markSynced(
      localId: 'employee-local-1',
      serverId: 'employee-server-1',
      membershipId: 'membership-1',
      cloudUserId: 'cloud-user-1',
    );

    final row = await (db.select(db.employees)
          ..where((e) => e.localId.equals('employee-local-1')))
        .getSingle();

    expect(row.serverId, 'employee-server-1');
    expect(row.membershipId, 'membership-1');
    expect(row.cloudUserId, 'cloud-user-1');
    expect(row.syncStatus, SyncStatus.settled);
  });
}
