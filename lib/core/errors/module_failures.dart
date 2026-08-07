/// Exceptions for Stages 9-12 (Receipts, Backup, Employees, Dashboard/
/// Reports).
///
/// These are deliberately plain `implements Exception` classes, NOT
/// subclasses of the existing `Failure` in core/errors/failure.dart.
/// `Failure` is declared `sealed`, and Dart only allows a sealed type to
/// be extended/implemented from within its own file — so a new subtype
/// can't be added from here without editing failure.dart directly. Since
/// this codebase is being merged from several concurrent sessions and
/// this response never saw the current state of failure.dart, editing it
/// blind risked silently discarding whatever the auth/audit/settings
/// stages already added there. These types are written so folding them
/// into that hierarchy later is a pure mechanical rename (same fields,
/// same constructors) once whoever owns that file can do it against the
/// real current version — see INTEGRATION.md.
library;

class EmployeeValidationException implements Exception {
  const EmployeeValidationException(this.message);
  final String message;
  @override
  String toString() => 'EmployeeValidationException: $message';
}

/// Thrown by EmployeeEngine.applyLeaveDecision when a leave request that
/// is already approved/denied is decided on again — mirrors the
/// backend's own one-way-transition rule in update_leave_status exactly
/// ("Can only update pending leave requests").
class LeaveTransitionException implements Exception {
  const LeaveTransitionException(this.message);
  final String message;
  @override
  String toString() => 'LeaveTransitionException: $message';
}

class ReceiptDataUnavailable implements Exception {
  const ReceiptDataUnavailable(this.saleId);
  final String saleId;
  @override
  String toString() => 'ReceiptDataUnavailable: no sale found for id $saleId';
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

/// Mirrors backend delete_backup/restore_backup's own path-traversal
/// guard — see backup_repository.dart's [BackupRepository.deleteBackup]
/// doc.
class InvalidBackupFileName implements Exception {
  const InvalidBackupFileName(this.fileName);
  final String fileName;

  /// So callers that catch both this and [BackupException] (see
  /// backup_screen.dart) can show either one's message the same way,
  /// without needing two differently-shaped catch branches.
  String get message => 'That backup file name isn\'t valid.';

  @override
  String toString() => 'InvalidBackupFileName: "$fileName" is not a valid backup file name';
}
