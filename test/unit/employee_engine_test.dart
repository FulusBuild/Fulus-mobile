import 'package:fulus_mobile/core/errors/module_failures.dart';
import 'package:fulus_mobile/domain/entities/employee.dart';
import 'package:fulus_mobile/domain/usecases/employee_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = EmployeeEngine();

  group('validateDraft', () {
    test('rejects an empty name', () {
      expect(
        () => engine.validateDraft(const EmployeeDraft(fullName: '   ')),
        throwsA(isA<EmployeeValidationException>()),
      );
    });

    test('rejects a name over 150 characters', () {
      final draft = EmployeeDraft(fullName: 'A' * 151);
      expect(() => engine.validateDraft(draft), throwsA(isA<EmployeeValidationException>()));
    });

    test('rejects negative salary', () {
      const draft = EmployeeDraft(fullName: 'Ada', salary: -1);
      expect(() => engine.validateDraft(draft), throwsA(isA<EmployeeValidationException>()));
    });

    test('accepts zero salary', () {
      const draft = EmployeeDraft(fullName: 'Ada', salary: 0);
      expect(() => engine.validateDraft(draft), returnsNormally);
    });

    test('rejects a malformed email', () {
      const draft = EmployeeDraft(fullName: 'Ada', email: 'not-an-email');
      expect(() => engine.validateDraft(draft), throwsA(isA<EmployeeValidationException>()));
    });

    test('accepts a well-formed email', () {
      const draft = EmployeeDraft(fullName: 'Ada', email: 'ada@example.com');
      expect(() => engine.validateDraft(draft), returnsNormally);
    });

    test('accepts a minimal valid draft', () {
      const draft = EmployeeDraft(fullName: 'Ada Lovelace');
      expect(() => engine.validateDraft(draft), returnsNormally);
    });
  });

  group('validateLeaveDraft', () {
    test('rejects end date before start date', () {
      final draft = LeaveRequestDraft(
        employeeId: 'e1',
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 9),
      );
      expect(() => engine.validateLeaveDraft(draft), throwsA(isA<EmployeeValidationException>()));
    });

    test('accepts a single-day leave request (start == end)', () {
      final draft = LeaveRequestDraft(
        employeeId: 'e1',
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 10),
      );
      expect(() => engine.validateLeaveDraft(draft), returnsNormally);
    });
  });

  group('validateBulkAttendance', () {
    test('rejects an employee id not on the roster', () {
      expect(
        () => engine.validateBulkAttendance(
          statusByEmployeeId: {'ghost': AttendanceStatus.present},
          rosterIds: {'e1', 'e2'},
        ),
        throwsA(isA<EmployeeValidationException>()),
      );
    });

    test('accepts a batch where every id is on the roster', () {
      expect(
        () => engine.validateBulkAttendance(
          statusByEmployeeId: {'e1': AttendanceStatus.present, 'e2': AttendanceStatus.late},
          rosterIds: {'e1', 'e2', 'e3'},
        ),
        returnsNormally,
      );
    });
  });

  group('applyLeaveDecision', () {
    LeaveRequest pending() => LeaveRequest(
          id: 'l1',
          employeeId: 'e1',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 3),
          status: LeaveStatus.pending,
        );

    test('approves a pending request and stamps decidedBy/decidedAt', () {
      final result = engine.applyLeaveDecision(
        current: pending(),
        newStatus: LeaveStatus.approved,
        decidedBy: 'owner-1',
        decidedAt: DateTime(2026, 7, 30),
      );
      expect(result.status, LeaveStatus.approved);
      expect(result.decidedBy, 'owner-1');
      expect(result.decidedAt, DateTime(2026, 7, 30));
    });

    test('throws when deciding an already-approved request again', () {
      final approved = pending().copyWith(status: LeaveStatus.approved, decidedBy: 'owner-1', decidedAt: DateTime(2026, 7, 20));
      expect(
        () => engine.applyLeaveDecision(
          current: approved,
          newStatus: LeaveStatus.denied,
          decidedBy: 'owner-2',
          decidedAt: DateTime(2026, 7, 31),
        ),
        throwsA(isA<LeaveTransitionException>()),
      );
    });
  });

  group('computeStats', () {
    Employee emp({required bool active, String? dept, double? salary}) => Employee(
          id: dept ?? 'e',
          fullName: 'Name',
          department: dept,
          salary: salary,
          isActive: active,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('sums salary across active employees only', () {
      final stats = engine.computeStats([
        emp(active: true, salary: 100),
        emp(active: true, salary: 50),
        emp(active: false, salary: 1000), // excluded: inactive
      ]);
      expect(stats.totalMonthlySalary, 150);
      expect(stats.totalEmployees, 3);
      expect(stats.activeEmployees, 2);
    });

    test('treats a null salary as 0 rather than throwing', () {
      final stats = engine.computeStats([emp(active: true, salary: null)]);
      expect(stats.totalMonthlySalary, 0);
    });

    test('counts departments only for employees that have one set', () {
      final stats = engine.computeStats([
        emp(active: true, dept: 'Sales'),
        emp(active: true, dept: 'Sales'),
        emp(active: true, dept: null),
      ]);
      expect(stats.departmentCounts, {'Sales': 2});
    });
  });

  group('summarizeAttendance', () {
    test('tallies present/absent/late independently', () {
      final records = [
        const AttendanceRecordStub(AttendanceStatus.present),
        const AttendanceRecordStub(AttendanceStatus.present),
        const AttendanceRecordStub(AttendanceStatus.absent),
        const AttendanceRecordStub(AttendanceStatus.late),
      ].map((s) => AttendanceRecord(id: 'a', employeeId: 'e1', date: DateTime(2026, 7, 1), status: s.status)).toList();

      final summary = engine.summarizeAttendance(employeeId: 'e1', month: 7, year: 2026, records: records);
      expect(summary.present, 2);
      expect(summary.absent, 1);
      expect(summary.late, 1);
      expect(summary.totalDays, 4);
    });
  });
}

/// Tiny helper so the table above reads as data, not boilerplate.
class AttendanceRecordStub {
  const AttendanceRecordStub(this.status);
  final AttendanceStatus status;
}
