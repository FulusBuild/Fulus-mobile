import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/usecases/employee_engine.dart';
import '../local/database/database.dart';
import 'employee_mapper.dart';

/// Every write here runs [EmployeeEngine]'s validation FIRST — see that
/// class's doc comment. This repository's own job is purely: translate
/// already-validated domain calls into Drift operations, and translate
/// rows back into entities. No business rule should ever be found only
/// here and not in EmployeeEngine.
class EmployeeRepositoryImpl implements EmployeeRepository {
  EmployeeRepositoryImpl({
    required AppDatabase db,
    EmployeeEngine engine = const EmployeeEngine(),
  })  : _db = db,
        _engine = engine;

  final AppDatabase _db;
  final EmployeeEngine _engine;

  // ── Roster ──────────────────────────────────────────────────────────────

  @override
  Future<Employee> createEmployee(EmployeeDraft draft) async {
    _engine.validateDraft(draft);
    final now = DateTime.now();
    final entity = draft.toEntity(id: Ulid().toString(), now: now);
    await _db.into(_db.employees).insert(entity.toCompanion());
    return entity;
  }

  @override
  Future<Employee> updateEmployee(String id, EmployeeDraft draft) async {
    _engine.validateDraft(draft);
    final existing = await getEmployeeById(id);
    if (existing == null) {
      throw StateError('Employee $id not found.');
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
      locationId: draft.locationId,
      updatedAt: DateTime.now(),
    );
    await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(updated.toCompanion());
    return updated;
  }

  @override
  Future<void> deactivateEmployee(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(
      EmployeesCompanion(
        isActive: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Stream<List<Employee>> watchEmployees({String? searchQuery, String? department, bool? isActive}) {
    final query = _db.select(_db.employees)..where((e) => e.deletedAt.isNull());
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final like = '%${searchQuery.trim()}%';
      query.where((e) =>
          e.fullName.like(like) | e.email.like(like) | e.department.like(like) | e.position.like(like));
    }
    if (department != null) {
      query.where((e) => e.department.like('%$department%'));
    }
    if (isActive != null) {
      query.where((e) => e.isActive.equals(isActive));
    }
    query.orderBy([(e) => OrderingTerm.asc(e.fullName)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<Employee?> getEmployeeById(String id) async {
    // Filtered the same as every other read in this file — without
    // this, a deactivated employee's id would still resolve here, and
    // updateEmployee() (which calls this to load the "existing" record
    // before applying edits) would silently be able to edit someone the
    // roster UI no longer shows at all.
    final row = await (_db.select(_db.employees)..where((e) => e.id.equals(id) & e.deletedAt.isNull())).getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<EmployeeStats> getStats() async {
    final rows = await (_db.select(_db.employees)..where((e) => e.deletedAt.isNull())).get();
    return _engine.computeStats(rows.map((r) => r.toDomain()).toList());
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
    final rosterIds = roster.map((e) => e.id).toSet();
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
