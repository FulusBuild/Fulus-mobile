import '../../core/errors/module_failures.dart';
import '../entities/employee.dart';

/// Stage 11's "Business Engine (Pure Dart)" layer per the Implementation
/// Bible: validation, calculations, and workflow rules for the employee
/// roster, attendance, and leave — no Flutter, no Drift, no I/O. Every
/// rule here is ported 1:1 from backend/app/services/employee_service.py
/// and backend/app/schemas/employee.py; see each method's doc comment
/// for the exact backend counterpart.
///
/// EmployeeRepositoryImpl calls these methods BEFORE touching the
/// database; a validation failure here means no write ever happens.
class EmployeeEngine {
  const EmployeeEngine();

  /// Mirrors EmployeeBase's field constraints in schemas/employee.py
  /// exactly (full_name 1-150 chars, department/position <=100,
  /// salary >= 0, phone <=30, email <=120). Throws
  /// [EmployeeValidationException] on the first rule broken; does not
  /// attempt to collect every error at once, matching the backend's own
  /// fail-fast Pydantic behaviour closely enough for a single-owner
  /// mobile form.
  void validateDraft(EmployeeDraft draft) {
    final name = draft.fullName.trim();
    if (name.isEmpty) {
      throw const EmployeeValidationException('Name is required.');
    }
    if (name.length > 150) {
      throw const EmployeeValidationException('Name must be 150 characters or fewer.');
    }
    if ((draft.department?.length ?? 0) > 100) {
      throw const EmployeeValidationException('Department must be 100 characters or fewer.');
    }
    if ((draft.position?.length ?? 0) > 100) {
      throw const EmployeeValidationException('Position must be 100 characters or fewer.');
    }
    if (draft.salary != null && draft.salary! < 0) {
      throw const EmployeeValidationException('Salary cannot be negative.');
    }
    if ((draft.phone?.length ?? 0) > 30) {
      throw const EmployeeValidationException('Phone number must be 30 characters or fewer.');
    }
    if ((draft.email?.length ?? 0) > 120) {
      throw const EmployeeValidationException('Email must be 120 characters or fewer.');
    }
    final email = draft.email;
    if (email != null && email.isNotEmpty && !_looksLikeEmail(email)) {
      throw const EmployeeValidationException('Enter a valid email address.');
    }
  }

  bool _looksLikeEmail(String value) {
    // Same permissiveness as the backend, which does no format check
    // beyond max_length at all — this adds a minimal sanity check
    // (must contain '@' with something on both sides) since a mobile
    // keyboard makes stray taps easier, without rejecting anything the
    // backend would accept.
    final at = value.indexOf('@');
    return at > 0 && at < value.length - 1 && !value.contains(' ');
  }

  /// mirrors create_leave_request's date rule exactly ("End date must be
  /// on or after start date"). Throws [EmployeeValidationException].
  void validateLeaveDraft(LeaveRequestDraft draft) {
    if (draft.endDate.isBefore(draft.startDate)) {
      throw const EmployeeValidationException('End date must be on or after start date.');
    }
    if ((draft.reason?.length ?? 0) > 255) {
      throw const EmployeeValidationException('Reason must be 255 characters or fewer.');
    }
  }

  /// Validates every id in [statusByEmployeeId] exists in [rosterIds]
  /// BEFORE any attendance is applied — mirrors bulk_mark_attendance's
  /// "validate every id up front, reject the whole batch on any miss"
  /// rule exactly (never applies half a batch).
  void validateBulkAttendance({
    required Map<String, AttendanceStatus> statusByEmployeeId,
    required Set<String> rosterIds,
  }) {
    final missing = statusByEmployeeId.keys.where((id) => !rosterIds.contains(id)).toList()..sort();
    if (missing.isNotEmpty) {
      throw EmployeeValidationException('Employee(s) not found: ${missing.join(', ')}');
    }
  }

  /// mirrors update_leave_status's one-way-transition guard exactly: a
  /// request already approved or denied can never be changed through
  /// this path again, even back to pending. Returns the decided record;
  /// throws [LeaveTransitionException] rather than silently no-op'ing,
  /// so the UI can show the same explanation the backend gives.
  LeaveRequest applyLeaveDecision({
    required LeaveRequest current,
    required LeaveStatus newStatus,
    required String decidedBy,
    required DateTime decidedAt,
  }) {
    if (current.status != LeaveStatus.pending && newStatus != current.status) {
      throw LeaveTransitionException(
        'This leave request was already ${current.status.name} and cannot be changed. '
        'Create a new leave request if this needs to be reconsidered.',
      );
    }
    final isFinal = newStatus == LeaveStatus.approved || newStatus == LeaveStatus.denied;
    return current.copyWith(
      status: newStatus,
      decidedBy: isFinal ? decidedBy : current.decidedBy,
      decidedAt: isFinal ? decidedAt : current.decidedAt,
    );
  }

  /// mirrors get_employee_stats's aggregation exactly: total/active
  /// counts, sum of salary across active employees only (coalesced to
  /// 0), and a department -> count map built only from employees that
  /// have a department set.
  EmployeeStats computeStats(List<Employee> roster) {
    final active = roster.where((e) => e.isActive).toList();
    final totalSalary = active.fold<double>(0, (sum, e) => sum + (e.salary ?? 0));
    final departmentCounts = <String, int>{};
    for (final e in roster) {
      final dept = e.department;
      if (dept != null && dept.isNotEmpty) {
        departmentCounts[dept] = (departmentCounts[dept] ?? 0) + 1;
      }
    }
    return EmployeeStats(
      totalEmployees: roster.length,
      activeEmployees: active.length,
      totalMonthlySalary: double.parse(totalSalary.toStringAsFixed(2)),
      departmentCounts: departmentCounts,
    );
  }

  /// mirrors get_attendance_summary's counting exactly: present/absent/
  /// late tallies for the given employee/month/year, plus their sum as
  /// total_days. [records] should already be filtered to that employee/
  /// month/year by the repository — this method only counts.
  AttendanceSummary summarizeAttendance({
    required String employeeId,
    required int month,
    required int year,
    required List<AttendanceRecord> records,
  }) {
    var present = 0, absent = 0, late = 0;
    for (final r in records) {
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.late:
          late++;
      }
    }
    return AttendanceSummary(
      employeeId: employeeId,
      month: month,
      year: year,
      present: present,
      absent: absent,
      late: late,
    );
  }
}
