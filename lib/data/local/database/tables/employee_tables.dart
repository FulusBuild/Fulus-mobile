import 'package:drift/drift.dart';

import '../tables.dart';

// Deliberately no `part` directive here — same reasoning as tables.dart's
// own header comment: this file's tables get their generated row classes
// via whichever file holds the @DriftDatabase(tables: [...]) annotation
// (database.dart), not from a part file of this one. See
// INTEGRATION.md for the exact two-line addition database.dart needs.

/// Stage 11's tables. Deliberately NOT using tables.dart's
/// `SyncableColumns` mixin (localId/serverId/syncStatus/deletedAt) —
/// the Implementation Bible is explicit that "Employees do NOT require
/// synchronization," so a serverId/syncStatus pair that could never
/// meaningfully change would only misstate what this data actually
/// does. Soft-delete is kept (matches backend Employee.is_deleted/
/// deleted_at) since that's a real product rule independent of sync;
/// everything sync-shaped is left out.
@DataClassName('EmployeeRow')
class Employees extends Table {
  TextColumn get id => text()();

  /// Nullable link into Users — see domain/entities/employee.dart's
  /// class doc for why this is optional (a roster row can exist for
  /// staff who have no login account, e.g. before they've claimed an
  /// invite). **Schema v4**: now a real Drift `references()` foreign
  /// key, not just a plain text column — Users exists in this schema
  /// and this is populated by the employee invite/claim flow
  /// (EmployeeInviteService) once an employee accepts an invite.
  TextColumn get authUserId => text().nullable().references(Users, #localId)();

  TextColumn get fullName => text().withLength(min: 1, max: 150)();
  TextColumn get role => text().nullable()();
  TextColumn get department => text().withLength(max: 100).nullable()();
  TextColumn get position => text().withLength(max: 100).nullable()();
  RealColumn get salary => real().nullable()();
  TextColumn get phone => text().withLength(max: 30).nullable()();
  TextColumn get email => text().withLength(max: 120).nullable()();
  DateTimeColumn get dateHired => dateTime().nullable()();
  TextColumn get locationId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete — mirrors backend Employee.is_deleted/deleted_at, not
  /// tables.dart's SyncableColumns.deletedAt (that one carries sync
  /// connotations this table intentionally has none of).
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum AttendanceStatusValue { present, absent, late }

@DataClassName('AttendanceRecordRow')
class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get employeeId => text().references(Employees, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get status => textEnum<AttendanceStatusValue>()();

  @override
  Set<Column> get primaryKey => {id};

  /// mirrors mark_attendance's upsert-by-(employee_id, date) rule —
  /// enforced here too so a bug in the repository layer can't silently
  /// create two attendance rows for the same employee on the same day.
  @override
  List<Set<Column>> get uniqueKeys => [
        {employeeId, date},
      ];
}

enum LeaveStatusValue { pending, approved, denied }

@DataClassName('LeaveRecordRow')
class LeaveRecords extends Table {
  TextColumn get id => text()();
  TextColumn get employeeId => text().references(Employees, #id)();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get reason => text().withLength(max: 255).nullable()();
  TextColumn get status => textEnum<LeaveStatusValue>().withDefault(const Constant('pending'))();

  /// Nullable auth-user id of the decider. **Schema v4**: now a real
  /// Drift `references()` foreign key into Users, same as
  /// Employees.authUserId above.
  TextColumn get decidedBy => text().nullable().references(Users, #localId)();
  DateTimeColumn get decidedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
