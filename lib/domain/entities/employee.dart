/// Employees — Stage 11 of the mobile roadmap.
///
/// Scope note (read this before touching this file): the backend's
/// `Employee` model (app/models/employee.py) is an HR roster record —
/// full_name, department, position, salary, attendance, leave. It is a
/// SEPARATE concept from the backend's `User` model (app/models/user.py),
/// which is the login/role/password account. The Product Design Bible's
/// Volume 9 mostly describes the *login* concept (Owner/Employee roles,
/// approval PIN, shift = login/logout) — that belongs to Stage 2 (Local
/// Authentication), already complete per HANDOVER-1.md, not to this file.
///
/// This module (Stage 11) owns the HR roster on top of whatever local
/// login accounts Stage 2 already created: who's on the team, their
/// role/position, contact details, attendance, and leave requests. Every
/// entity below is local-only per the Implementation Bible ("Employees do
/// NOT require synchronization").
///
/// [authUserId] is the deliberate seam to Stage 2: when a roster entry
/// also has its own device login (the common case — a till employee who
/// signs in), this holds that local auth user's id. It is nullable
/// because a roster can legitimately contain someone with no device
/// login of their own (e.g. an owner tracking a delivery rider's pay who
/// never touches the app) — the Bible's Volume 9 model assumes every
/// employee logs in, but the backend's Employee model (payroll/HR) does
/// not require that, and this mobile roster deliberately supports both.
class Employee {
  const Employee({
    required this.id,
    this.authUserId,
    required this.fullName,
    this.role,
    this.department,
    this.position,
    this.salary,
    this.phone,
    this.email,
    this.dateHired,
    this.locationId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Links to the Stage 2 local auth account, if this employee also has
  /// their own device login. See class doc above.
  final String? authUserId;

  final String fullName;

  /// Free text today ("Cashier", "Manager"), not the fixed Owner/Employee
  /// permission-bundle enum from Volume 9 Decision 30 — that enum is
  /// Stage 2's auth-role concept and lives with the AuthUser, not here.
  /// This field is the HR title shown on the roster and in Reports, kept
  /// deliberately separate so this module never needs to know about, or
  /// duplicate, Stage 2's permission bundle.
  final String? role;

  final String? department;
  final String? position;

  /// Mirrors backend Employee.salary. Nullable/defaults to 0 at the
  /// repository boundary — many small businesses using this roster won't
  /// enter a figure at all, and EmployeeStats.totalMonthlySalary treats a
  /// missing value as 0, matching the backend's own `default=0.0`.
  final double? salary;
  final String? phone;
  final String? email;
  final DateTime? dateHired;

  /// Nullable, matching backend migration 0022's own choice to leave
  /// Employee.location_id optional where Sale/Expense/Income/
  /// StockMovement/Shift require it (Architecture Section 7a) — a
  /// single-shop business never needs to set this.
  final String? locationId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Employee copyWith({
    String? fullName,
    Object? role = _sentinel,
    Object? department = _sentinel,
    Object? position = _sentinel,
    Object? salary = _sentinel,
    Object? phone = _sentinel,
    Object? email = _sentinel,
    Object? dateHired = _sentinel,
    Object? locationId = _sentinel,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id,
      authUserId: authUserId,
      fullName: fullName ?? this.fullName,
      role: role == _sentinel ? this.role : role as String?,
      department: department == _sentinel ? this.department : department as String?,
      position: position == _sentinel ? this.position : position as String?,
      salary: salary == _sentinel ? this.salary : salary as double?,
      phone: phone == _sentinel ? this.phone : phone as String?,
      email: email == _sentinel ? this.email : email as String?,
      dateHired: dateHired == _sentinel ? this.dateHired : dateHired as DateTime?,
      locationId: locationId == _sentinel ? this.locationId : locationId as String?,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _sentinel = Object();

/// The not-yet-persisted input to [EmployeeRepository.createEmployee] —
/// same split as CustomerDraft elsewhere in this codebase: everything an
/// owner enters on the "Add team member" form, minus the identity fields
/// only assigned at creation time.
class EmployeeDraft {
  const EmployeeDraft({
    required this.fullName,
    this.authUserId,
    this.role,
    this.department,
    this.position,
    this.salary,
    this.phone,
    this.email,
    this.dateHired,
    this.locationId,
  });

  final String fullName;
  final String? authUserId;
  final String? role;
  final String? department;
  final String? position;
  final double? salary;
  final String? phone;
  final String? email;
  final DateTime? dateHired;
  final String? locationId;
}

enum AttendanceStatus { present, absent, late }

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
  });

  final String id;
  final String employeeId;

  /// Calendar day only — matches the backend's Date column and the
  /// one-record-per-employee-per-day uniqueness rule in
  /// mark_attendance/bulk_mark_attendance.
  final DateTime date;
  final AttendanceStatus status;
}

/// Present/absent/late counts for one employee over one month — mirrors
/// employee_service.get_attendance_summary's return shape exactly.
class AttendanceSummary {
  const AttendanceSummary({
    required this.employeeId,
    required this.month,
    required this.year,
    required this.present,
    required this.absent,
    required this.late,
  });

  final String employeeId;
  final int month;
  final int year;
  final int present;
  final int absent;
  final int late;

  int get totalDays => present + absent + late;
}

enum LeaveStatus { pending, approved, denied }

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
    this.decidedBy,
    this.decidedAt,
  });

  final String id;
  final String employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final LeaveStatus status;

  /// The local auth user id of whoever approved/denied — nullable while
  /// pending, matching the backend's own approved_by column exactly.
  final String? decidedBy;
  final DateTime? decidedAt;

  LeaveRequest copyWith({
    LeaveStatus? status,
    String? decidedBy,
    DateTime? decidedAt,
  }) {
    return LeaveRequest(
      id: id,
      employeeId: employeeId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: status ?? this.status,
      decidedBy: decidedBy ?? this.decidedBy,
      decidedAt: decidedAt ?? this.decidedAt,
    );
  }
}

class LeaveRequestDraft {
  const LeaveRequestDraft({
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    this.reason,
  });

  final String employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
}

/// Roster-wide counters — mirrors employee_service.get_employee_stats.
class EmployeeStats {
  const EmployeeStats({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.totalMonthlySalary,
    required this.departmentCounts,
  });

  final int totalEmployees;
  final int activeEmployees;

  /// Sum of `salary` across active, non-deleted employees — mirrors
  /// employee_service.get_employee_stats exactly (coalesced to 0).
  final double totalMonthlySalary;
  final Map<String, int> departmentCounts;
}
