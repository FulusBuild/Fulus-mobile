import 'package:drift/drift.dart';
import '../../core/money/money.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/module_failures.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/permission.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/permission_repository.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/usecases/employee_engine.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import 'employee_mapper.dart';

/// Every write here runs [EmployeeEngine]'s validation FIRST — see that
/// class's doc comment. This repository's own job is purely: translate
/// already-validated domain calls into Drift operations, and translate
/// rows back into entities. No business rule should ever be found only
/// here and not in EmployeeEngine.
class EmployeeRepositoryImpl implements EmployeeRepository {
  EmployeeRepositoryImpl({
    required AppDatabase db,
    required AuthRepository authRepository,
    required PermissionRepository permissionRepository,
    required SyncQueue syncQueue,
    EmployeeEngine engine = const EmployeeEngine(),
  })  : _db = db,
        _authRepository = authRepository,
        _permissionRepository = permissionRepository,
        _syncQueue = syncQueue,
        _engine = engine;

  final AppDatabase _db;
  final AuthRepository _authRepository;
  final PermissionRepository _permissionRepository;
  final SyncQueue _syncQueue;
  final EmployeeEngine _engine;

  Future<void> _requireManageEmployees() async {
    final user = _authRepository.currentUser;
    final allowed = user != null &&
        await _permissionRepository.hasPermission(
          userId: user.id,
          role: user.role,
          permission: Permission.manageEmployees,
        );
    if (!allowed) {
      throw const AuthFailure.forbidden();
    }
  }

  Future<void> _assertEmployeeInActiveLocation(String? employeeLocationId) async {
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    // No session row is possible only in pre-session/local test contexts.
    // Once a session exists, a missing active location or a mismatch is a
    // hard isolation failure, not a reason to show the business-wide roster.
    if (session != null &&
        (session.activeLocationId == null ||
            employeeLocationId != session.activeLocationId)) {
      throw StateError('Employee is outside the active location.');
    }
  }

  // ── Roster ──────────────────────────────────────────────────────────────

  @override
  Future<Employee> createEmployee(EmployeeDraft draft) async {
    await _requireManageEmployees();
    _engine.validateDraft(draft);
    final session = await (_db.select(_db.sessions)
          ..where((row) => row.id.equals('current')))
        .getSingleOrNull();
    if (session != null && session.activeLocationId == null) {
      throw StateError('Select an active location before creating an employee.');
    }
    if (session?.activeLocationId != null &&
        draft.locationId != null &&
        draft.locationId != session!.activeLocationId) {
      throw StateError('Employees can only be created in the active location.');
    }
    final effectiveDraft = EmployeeDraft(
      fullName: draft.fullName,
      authUserId: draft.authUserId,
      role: draft.role,
      department: draft.department,
      position: draft.position,
      salary: draft.salary,
      phone: draft.phone,
      email: draft.email,
      dateHired: draft.dateHired,
      locationId: session?.activeLocationId ?? draft.locationId,
    );
    if (effectiveDraft.locationId == null) {
      throw StateError('Employee roster ownership requires an explicit location.');
    }
    final now = DateTime.now();
    final entity = effectiveDraft.toEntity(id: Ulid().toString(), now: now);
    await _db.transaction(() async {
      await _db.into(_db.employees).insert(entity.toCompanion());
      await _syncQueue.enqueue(SyncTask.createEmployee(entity.id));
    });
    return entity;
  }

  @override
  Future<Employee> updateEmployee(String id, EmployeeDraft draft) async {
    await _requireManageEmployees();
    _engine.validateDraft(draft);
    final existing = await getEmployeeById(id);
    if (existing == null) {
      throw StateError('Employee $id not found.');
    }
    if ((draft.email ?? '').trim().toLowerCase() !=
        (existing.email ?? '').trim().toLowerCase()) {
      throw const EmployeeValidationException(
        'An employee login email cannot be changed after the employee is created.',
      );
    }
    if (draft.locationId != null && draft.locationId != existing.locationId) {
      throw StateError(
        'Employee location transfer requires an explicit authorized transfer flow.',
      );
    }
    final updated = existing.copyWith(
      fullName: draft.fullName.trim(),
      role: draft.role,
      department: draft.department,
      position: draft.position,
      salary: draft.salary,
      phone: draft.phone,
      email: draft.email,
      dateHired: draft.dateHired,
      locationId: existing.locationId,
      updatedAt: DateTime.now(),
    );
    await _db.transaction(() async {
      await (_db.update(_db.employees)..where((e) => e.localId.equals(id))).write(
        EmployeesCompanion(
          fullName: Value(updated.fullName), role: Value(updated.role),
          department: Value(updated.department), position: Value(updated.position),
          salary: Value(updated.salary), phone: Value(updated.phone),
          email: Value(updated.email), dateHired: Value(updated.dateHired),
          locationId: Value(updated.locationId), updatedAt: Value(updated.updatedAt),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateEmployee(id));
    });
    return updated;
  }

  @override
  Future<void> deactivateEmployee(String id) async {
    await _requireManageEmployees();
    final now = DateTime.now();
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.employees,
      )..where((e) => e.localId.equals(id))).getSingleOrNull();
      if (row == null) {
        throw StateError('Employee $id not found.');
      }
      await _assertEmployeeInActiveLocation(row.locationId);
      final currentUserId = _authRepository.currentUser?.id;
      if (currentUserId != null &&
          (row.authUserId == currentUserId || row.cloudUserId == currentUserId)) {
        throw const AuthFailure.forbidden();
      }
      await (_db.update(_db.employees)..where((e) => e.localId.equals(id))).write(
        EmployeesCompanion(
          isActive: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      // Deactivating the roster record alone never revoked sign-in
      // access for staff with a linked login — Users.isActive is what
      // auth_repository_impl actually checks, and this row's own
      // isActive is a separate flag on a separate table. Cascading it
      // here is what makes "they'll no longer be able to sign in"
      // (the confirmation dialog's own claim) actually true.
      final authUserId = row.authUserId ?? row.cloudUserId;
      if (authUserId != null) {
        await (_db.update(
          _db.users,
        )..where((u) => u.localId.equals(authUserId))).write(
          const UsersCompanion(isActive: Value(false)),
        );
      }
      await _syncQueue.enqueue(SyncTask.updateEmployee(id));
    });
  }

  /// The reverse of [deactivateEmployee] — restores both the roster
  /// record and, symmetrically, sign-in access for a linked account.
  @override
  Future<void> reactivateEmployee(String id) async {
    await _requireManageEmployees();
    final now = DateTime.now();
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.employees,
      )..where((e) => e.localId.equals(id))).getSingleOrNull();
      if (row == null) {
        throw StateError('Employee $id not found.');
      }
      await _assertEmployeeInActiveLocation(row.locationId);
      await (_db.update(_db.employees)..where((e) => e.localId.equals(id))).write(
        EmployeesCompanion(
          isActive: const Value(true),
          deletedAt: const Value(null),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      final authUserId = row.authUserId ?? row.cloudUserId;
      if (authUserId != null) {
        await (_db.update(
          _db.users,
        )..where((u) => u.localId.equals(authUserId))).write(
          const UsersCompanion(isActive: Value(true)),
        );
      }
      await _syncQueue.enqueue(SyncTask.updateEmployee(id));
    });
  }

  @override
  Stream<List<Employee>> watchEmployees({
    String? searchQuery,
    String? department,
    bool? isActive,
  }) {
    final query = _db.select(_db.employees).join([
      leftOuterJoin(
        _db.sessions,
        _db.sessions.id.equals('current'),
      ),
    ])
      ..where(
        _db.sessions.id.isNull() |
            _db.employees.locationId.equalsExp(_db.sessions.activeLocationId),
      );

    // Active/default roster views hide soft-deleted rows. The explicit
    // inactive view must do the opposite so deactivated employees remain
    // recoverable for reactivation and audit history.
    if (isActive == false) {
      query.where(_db.employees.isActive.equals(false));
    } else {
      query.where(_db.employees.deletedAt.isNull());
      if (isActive == true) {
        query.where(_db.employees.isActive.equals(true));
      }
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final like = '%${searchQuery.trim()}%';
      query.where(
        _db.employees.fullName.like(like) |
            _db.employees.email.like(like) |
            _db.employees.department.like(like) |
            _db.employees.position.like(like),
      );
    }
    if (department != null) {
      query.where(_db.employees.department.like('%$department%'));
    }
    if (isActive != null) {
      query.where(_db.employees.isActive.equals(isActive));
    }
    query.orderBy([OrderingTerm.asc(_db.employees.fullName)]);
    return query.watch().map(
          (rows) => rows
              .map((row) => row.readTable(_db.employees).toDomain())
              .toList(),
        );
  }

  @override
  Future<Employee?> getEmployeeById(
    String id, {
    bool includeInactive = false,
    bool forSync = false,
  }) async {
    // Filtered the same as every other read in this file by default —
    // without this, a deactivated employee's id would still resolve
    // here, and updateEmployee() (which calls this to load the
    // "existing" record before applying edits) would silently be able
    // to edit someone the roster UI no longer shows at all.
    // includeInactive exists for the one caller that legitimately does
    // need a deactivated employee by id — EmployeeDetailScreen, so a
    // deactivated-employees view has somewhere real to navigate to for
    // reactivating one. updateEmployee's own call site doesn't pass it,
    // so this stays exactly as protective as before for that path.
    final query = _db.select(_db.employees)..where((e) => e.localId.equals(id));
    if (!includeInactive) {
      query.where((e) => e.deletedAt.isNull());
    }
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    if (!forSync) {
      final session = await (_db.select(_db.sessions)
            ..where((session) => session.id.equals('current')))
          .getSingleOrNull();
      if (session != null &&
          (session.activeLocationId == null ||
              row.locationId != session.activeLocationId)) {
        return null;
      }
    }
    return row.toDomain();
  }

  @override
  Future<EmployeeStats> getStats() async {
    final session = await (_db.select(_db.sessions)
          ..where((session) => session.id.equals('current')))
        .getSingleOrNull();
    final query = _db.select(_db.employees)
      ..where((employee) => employee.deletedAt.isNull());
    if (session != null) {
      final locationId = session.activeLocationId;
      if (locationId == null) {
        return _engine.computeStats(const <Employee>[]);
      }
      query.where((employee) => employee.locationId.equals(locationId));
    }
    final rows = await query.get();
    return _engine.computeStats(rows.map((row) => row.toDomain()).toList());
  }

  @override
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? membershipId,
    String? cloudUserId,
    String? operationId,
  }) async {
    await _db.transaction(() async {
      var hasNewerMutation = false;
      if (operationId != null) {
        final current = await (_db.select(_db.syncQueueItems)
              ..where((q) => q.id.equals(operationId)))
            .getSingleOrNull();
        if (current == null) {
          hasNewerMutation = true;
        } else {
          hasNewerMutation = await _syncQueue.hasNewerQueueMutation(
            entityType: 'employee',
            entityLocalId: localId,
            operationId: operationId,
            enqueuedAt: current.enqueuedAt,
          );
        }
      }
      await (_db.update(_db.employees)..where((e) => e.localId.equals(localId))).write(
        EmployeesCompanion(
          serverId: Value(serverId),
          membershipId: Value(membershipId),
          cloudUserId: Value(cloudUserId),
          syncStatus: Value(hasNewerMutation ? SyncStatus.pending : SyncStatus.settled),
        ),
      );
    });
  }

  @override
  Future<void> reconcileServerState({
    required String serverId,
    String? clientReference,
    required String? membershipId,
    required String? cloudUserId,
    required String fullName,
    required String? role,
    required String? department,
    required String? position,
    required Money? salary,
    required String? phone,
    required String? email,
    required DateTime? dateHired,
    required String? locationId,
    required bool isActive,
    required DateTime updatedAt,
    required DateTime createdAt,
  }) async {
    final existingByServer = await (_db.select(_db.employees)
          ..where((e) => e.serverId.equals(serverId)))
        .getSingleOrNull();
    final existing = existingByServer ?? (clientReference == null || clientReference.isEmpty
        ? null
        : await (_db.select(_db.employees)
              ..where((e) => e.localId.equals(clientReference)))
            .getSingleOrNull());
    final localId = existing?.localId ?? Ulid().toString();
    final resolvedIncomingLocationId = await _resolveLocationLocalId(locationId);
    if (locationId != null && resolvedIncomingLocationId == null) {
      throw StateError('Employee owner location is not available locally yet.');
    }
    final effectiveLocationId =
        locationId == null ? existing?.locationId : resolvedIncomingLocationId;
    await _db.transaction(() async {
      if (existing == null) {
        await _db.into(_db.employees).insert(
          EmployeesCompanion(
            localId: Value(localId),
            serverId: Value(serverId),
            membershipId: Value(membershipId),
            cloudUserId: Value(cloudUserId),
            fullName: Value(fullName),
            role: Value(role),
            department: Value(department),
            position: Value(position),
            salary: Value(salary),
            phone: Value(phone),
            email: Value(email),
            dateHired: Value(dateHired),
            locationId: Value(effectiveLocationId),
            isActive: Value(isActive),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            deletedAt: Value(isActive ? null : updatedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      } else {
        await (_db.update(_db.employees)..where((e) => e.localId.equals(localId))).write(
          EmployeesCompanion(
            serverId: Value(serverId),
            membershipId: Value(membershipId),
            cloudUserId: Value(cloudUserId),
            fullName: Value(fullName),
            role: Value(role),
            department: Value(department),
            position: Value(position),
            salary: Value(salary),
            phone: Value(phone),
            email: Value(email),
            dateHired: Value(dateHired),
            locationId: Value(effectiveLocationId),
            isActive: Value(isActive),
            deletedAt: Value(isActive ? null : updatedAt),
            updatedAt: Value(updatedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }
      if (cloudUserId != null && cloudUserId.isNotEmpty) {
        await (_db.update(_db.users)..where((u) => u.localId.equals(cloudUserId))).write(
          UsersCompanion(isActive: Value(isActive), updatedAt: Value(updatedAt)),
        );
      }
    });
  }

  Future<String?> _resolveLocationLocalId(String? id) async {
    if (id == null || id.isEmpty) return null;
    final local = await (_db.select(_db.locations)
          ..where((location) => location.localId.equals(id)))
        .getSingleOrNull();
    if (local != null) return local.localId;
    final server = await (_db.select(_db.locations)
          ..where((location) => location.serverId.equals(id)))
        .getSingleOrNull();
    return server?.localId;
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final employee = await (_db.select(_db.employees)
          ..where((e) => e.serverId.equals(serverId)))
        .getSingleOrNull();
    await (_db.update(_db.employees)..where((e) => e.serverId.equals(serverId))).write(
      EmployeesCompanion(
        isActive: const Value(false),
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
    final authUserId = employee?.authUserId ?? employee?.cloudUserId;
    if (authUserId != null && authUserId.isNotEmpty) {
      await (_db.update(_db.users)..where((u) => u.localId.equals(authUserId))).write(
        const UsersCompanion(isActive: Value(false)),
      );
    }
  }

  // ── Attendance ──────────────────────────────────────────────────────────

  @override
  Future<AttendanceRecord> markAttendance({
    required String employeeId,
    required DateTime date,
    required AttendanceStatus status,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    final existing = await (_db.select(_db.attendanceRecords)
          ..where((a) => a.employeeId.equals(employeeId) & a.date.equals(day)))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.attendanceRecords)..where((a) => a.id.equals(existing.id))).write(
        AttendanceRecordsCompanion(status: Value(attendanceStatusToDb(status))),
      );
      return AttendanceRecord(id: existing.id, employeeId: employeeId, date: day, status: status);
    }

    final id = Ulid().toString();
    await _db.into(_db.attendanceRecords).insert(
          AttendanceRecordsCompanion.insert(
            id: id,
            employeeId: employeeId,
            date: day,
            status: attendanceStatusToDb(status),
          ),
        );
    return AttendanceRecord(id: id, employeeId: employeeId, date: day, status: status);
  }

  @override
  Future<List<AttendanceRecord>> bulkMarkAttendance({
    required DateTime date,
    required Map<String, AttendanceStatus> statusByEmployeeId,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    final roster = await (_db.select(_db.employees)..where((e) => e.deletedAt.isNull())).get();
    final rosterIds = roster.map((e) => e.localId).toSet();
    _engine.validateBulkAttendance(statusByEmployeeId: statusByEmployeeId, rosterIds: rosterIds);

    final results = <AttendanceRecord>[];
    await _db.transaction(() async {
      for (final entry in statusByEmployeeId.entries) {
        results.add(await markAttendance(employeeId: entry.key, date: day, status: entry.value));
      }
    });
    return results;
  }

  @override
  Future<List<AttendanceRecord>> getAttendance({String? employeeId, DateTime? dateFrom, DateTime? dateTo}) async {
    final query = _db.select(_db.attendanceRecords);
    if (employeeId != null) query.where((a) => a.employeeId.equals(employeeId));
    if (dateFrom != null) query.where((a) => a.date.isBiggerOrEqualValue(dateFrom));
    if (dateTo != null) query.where((a) => a.date.isSmallerOrEqualValue(dateTo));
    query.orderBy([(a) => OrderingTerm.desc(a.date)]);
    final rows = await query.get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<AttendanceSummary> getAttendanceSummary({required String employeeId, required int month, required int year}) async {
    final rows = await (_db.select(_db.attendanceRecords)..where((a) => a.employeeId.equals(employeeId))).get();
    final inMonth = rows.where((r) => r.date.month == month && r.date.year == year).map((r) => r.toDomain()).toList();
    return _engine.summarizeAttendance(employeeId: employeeId, month: month, year: year, records: inMonth);
  }

  // ── Leave ───────────────────────────────────────────────────────────────

  @override
  Future<LeaveRequest> createLeaveRequest(LeaveRequestDraft draft) async {
    _engine.validateLeaveDraft(draft);
    final id = Ulid().toString();
    await _db.into(_db.leaveRecords).insert(
          LeaveRecordsCompanion.insert(
            id: id,
            employeeId: draft.employeeId,
            startDate: draft.startDate,
            endDate: draft.endDate,
            reason: Value(draft.reason),
          ),
        );
    return LeaveRequest(
      id: id,
      employeeId: draft.employeeId,
      startDate: draft.startDate,
      endDate: draft.endDate,
      reason: draft.reason,
      status: LeaveStatus.pending,
    );
  }

  @override
  Future<LeaveRequest> decideLeaveRequest({
    required String leaveId,
    required LeaveStatus status,
    required String decidedBy,
  }) async {
    final row = await (_db.select(_db.leaveRecords)..where((l) => l.id.equals(leaveId))).getSingleOrNull();
    if (row == null) {
      throw StateError('Leave request $leaveId not found.');
    }
    final decided = _engine.applyLeaveDecision(
      current: row.toDomain(),
      newStatus: status,
      decidedBy: decidedBy,
      decidedAt: DateTime.now(),
    );
    await (_db.update(_db.leaveRecords)..where((l) => l.id.equals(leaveId))).write(
      LeaveRecordsCompanion(
        status: Value(leaveStatusToDb(decided.status)),
        decidedBy: Value(decided.decidedBy),
        decidedAt: Value(decided.decidedAt),
      ),
    );
    return decided;
  }

  @override
  Future<List<LeaveRequest>> listLeaveRequests({String? employeeId, LeaveStatus? status}) async {
    final query = _db.select(_db.leaveRecords);
    if (employeeId != null) query.where((l) => l.employeeId.equals(employeeId));
    if (status != null) query.where((l) => l.status.equalsValue(leaveStatusToDb(status)));
    query.orderBy([(l) => OrderingTerm.desc(l.startDate)]);
    final rows = await query.get();
    return rows.map((r) => r.toDomain()).toList();
  }
}
