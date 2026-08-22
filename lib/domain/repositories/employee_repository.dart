import '../entities/employee.dart';

/// Architecture Section 4's repository pattern, applied to Stage 11.
/// One repository covering roster + attendance + leave, mirroring the
/// backend's own single employee_service.py module rather than being
/// split into three repositories for what is, product-wise, one
/// cohesive concern.
///
/// Fully local, fully offline — per the Implementation Bible ("Employees
/// do NOT require synchronization") every method here works with no
/// connectivity, always, forever, not just "for now."
abstract class EmployeeRepository {
  // ── Roster ──────────────────────────────────────────────────────────────

  Future<Employee> createEmployee(EmployeeDraft draft);

  Future<Employee> updateEmployee(String id, EmployeeDraft draft);

  /// Soft delete — mirrors employee_service.delete_employee (is_deleted +
  /// deleted_at + forces is_active false), never a hard row delete, so a
  /// departed employee's attendance/leave/sales-performance history
  /// stays intact for Reports. Also revokes sign-in access when this
  /// roster row has a linked login account (`authUserId`) — see
  /// [reactivateEmployee] for the reverse.
  Future<void> deactivateEmployee(String id);

  /// Restores a deactivated employee — the roster record, and sign-in
  /// access if they have a linked login account. Recoverable by design:
  /// nothing about [deactivateEmployee] is a hard delete.
  Future<void> reactivateEmployee(String id);

  Stream<List<Employee>> watchEmployees({
    String? searchQuery,
    String? department,
    bool? isActive,
  });

  /// Null for an id that doesn't exist OR that belongs to a
  /// deactivated employee — consistent with every list/stream method
  /// on this repository, all of which exclude deactivated employees.
  Future<Employee?> getEmployeeById(String id, {bool includeInactive = false});

  Future<EmployeeStats> getStats();

  // ── Attendance ──────────────────────────────────────────────────────────

  /// Upsert-by-(employeeId, date) — mirrors mark_attendance exactly: a
  /// second call for the same employee and day updates the existing
  /// record's status rather than creating a duplicate.
  Future<AttendanceRecord> markAttendance({
    required String employeeId,
    required DateTime date,
    required AttendanceStatus status,
  });

  /// Same upsert rule as [markAttendance], applied to every entry in one
  /// transaction — mirrors bulk_mark_attendance, including its
  /// all-or-nothing validation (every employeeId must already exist on
  /// the roster, or the whole batch is rejected).
  Future<List<AttendanceRecord>> bulkMarkAttendance({
    required DateTime date,
    required Map<String, AttendanceStatus> statusByEmployeeId,
  });

  Future<List<AttendanceRecord>> getAttendance({
    String? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  });

  Future<AttendanceSummary> getAttendanceSummary({
    required String employeeId,
    required int month,
    required int year,
  });

  // ── Leave ───────────────────────────────────────────────────────────────

  Future<LeaveRequest> createLeaveRequest(LeaveRequestDraft draft);

  /// Approve or deny — mirrors update_leave_status's one-way-transition
  /// rule (EmployeeEngine.applyLeaveDecision enforces it before this is
  /// ever called; this method persists the already-validated result).
  Future<LeaveRequest> decideLeaveRequest({
    required String leaveId,
    required LeaveStatus status,
    required String decidedBy,
  });

  Future<List<LeaveRequest>> listLeaveRequests({
    String? employeeId,
    LeaveStatus? status,
  });
}
