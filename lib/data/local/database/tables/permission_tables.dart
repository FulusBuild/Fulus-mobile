import 'package:drift/drift.dart';

import '../../../../domain/entities/permission.dart';
import '../tables.dart';

// Deliberately no `part` directive here — same reasoning as
// employee_tables.dart's own header comment: this table's generated row
// class comes from database.dart's @DriftDatabase part file, not one of
// its own.

/// The individual capability grants behind domain/entities/permission.
/// dart's `Permission` enum — schemaVersion 10.
///
/// Deliberately NOT using tables.dart's `SyncableColumns` mixin, same
/// reasoning as Employees: permission grants are local-device
/// authorization state, not business data with a sync story of its own.
/// If/when multi-device sync of staff access ever becomes real, it
/// should sync as part of whatever carries the Users row itself, not
/// as a separately-syncable table that could drift out of step with it.
///
/// One row per (userId, permission) actually granted — absence of a
/// row means "not granted," there's no separate boolean to go stale.
/// `AuthRole.owner` logins never get rows here at all (see
/// PermissionRepository.hasPermission's doc comment for why that's a
/// deliberate structural exemption, not just "owner happens to have
/// every row").
@DataClassName('UserPermissionRow')
class UserPermissions extends Table {
  TextColumn get userId => text().references(Users, #localId)();
  TextColumn get permission => textEnum<Permission>()();

  /// Who granted it and when — an audit trail for a table that exists
  /// specifically to answer "who can do what and why," matching this
  /// codebase's existing habit for other sensitive-decision columns
  /// (LeaveRecords.decidedBy/decidedAt in employee_tables.dart).
  /// Nullable only for rows seeded by `Permission.defaultsForRole` at
  /// account-creation time before any owner has explicitly touched an
  /// individual toggle.
  TextColumn get grantedBy => text().nullable().references(Users, #localId)();
  DateTimeColumn get grantedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, permission};
}
