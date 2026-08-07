import 'package:drift/drift.dart';

import '../../domain/entities/employee.dart';
import '../local/database/database.dart';
import '../local/database/tables/employee_tables.dart';

extension EmployeeRowMapper on EmployeeRow {
  Employee toDomain() {
    return Employee(
      id: id,
      authUserId: authUserId,
      fullName: fullName,
      role: role,
      department: department,
      position: position,
      salary: salary,
      phone: phone,
      email: email,
      dateHired: dateHired,
      locationId: locationId,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension EmployeeDomainMapper on Employee {
  EmployeesCompanion toCompanion() {
    return EmployeesCompanion(
      id: Value(id),
      authUserId: Value(authUserId),
      fullName: Value(fullName),
      role: Value(role),
      department: Value(department),
      position: Value(position),
      salary: Value(salary),
      phone: Value(phone),
      email: Value(email),
      dateHired: Value(dateHired),
      locationId: Value(locationId),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }
}

extension EmployeeDraftMapper on EmployeeDraft {
  Employee toEntity({required String id, required DateTime now}) {
    return Employee(
      id: id,
      authUserId: authUserId,
      fullName: fullName.trim(),
      role: role,
      department: department,
      position: position,
      salary: salary,
      phone: phone,
      email: email,
      dateHired: dateHired,
      locationId: locationId,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

AttendanceStatus attendanceStatusFromDb(AttendanceStatusValue v) {
  switch (v) {
    case AttendanceStatusValue.present:
      return AttendanceStatus.present;
    case AttendanceStatusValue.absent:
      return AttendanceStatus.absent;
    case AttendanceStatusValue.late:
      return AttendanceStatus.late;
  }
}

AttendanceStatusValue attendanceStatusToDb(AttendanceStatus v) {
  switch (v) {
    case AttendanceStatus.present:
      return AttendanceStatusValue.present;
    case AttendanceStatus.absent:
      return AttendanceStatusValue.absent;
    case AttendanceStatus.late:
      return AttendanceStatusValue.late;
  }
}

extension AttendanceRecordRowMapper on AttendanceRecordRow {
  AttendanceRecord toDomain() {
    return AttendanceRecord(
      id: id,
      employeeId: employeeId,
      date: date,
      status: attendanceStatusFromDb(status),
    );
  }
}

LeaveStatus leaveStatusFromDb(LeaveStatusValue v) {
  switch (v) {
    case LeaveStatusValue.pending:
      return LeaveStatus.pending;
    case LeaveStatusValue.approved:
      return LeaveStatus.approved;
    case LeaveStatusValue.denied:
      return LeaveStatus.denied;
  }
}

LeaveStatusValue leaveStatusToDb(LeaveStatus v) {
  switch (v) {
    case LeaveStatus.pending:
      return LeaveStatusValue.pending;
    case LeaveStatus.approved:
      return LeaveStatusValue.approved;
    case LeaveStatus.denied:
      return LeaveStatusValue.denied;
  }
}

extension LeaveRecordRowMapper on LeaveRecordRow {
  LeaveRequest toDomain() {
    return LeaveRequest(
      id: id,
      employeeId: employeeId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: leaveStatusFromDb(status),
      decidedBy: decidedBy,
      decidedAt: decidedAt,
    );
  }
}
