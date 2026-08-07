import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/audit_log.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/audit_repository.dart';
import '../local/database/database.dart';

class AuditRepositoryImpl implements AuditRepository {
  AuditRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> log({
    String? userId,
    required String action,
    required String module,
    String? recordId,
    Map<String, dynamic>? details,
  }) async {
    // Mirrors audit_service.log's own try/except-and-swallow exactly
    // (verified directly) — this must never throw, so the entire body
    // is wrapped, not just the insert.
    try {
      await _db.into(_db.auditLogs).insert(
            AuditLogsCompanion.insert(
              localId: Ulid().toString(),
              userId: Value(userId),
              action: action,
              module: module,
              recordId: Value(recordId),
              details: Value(details != null ? jsonEncode(details) : null),
              createdAt: DateTime.now(),
              syncStatus: SyncStatus.pending,
              updatedAt: DateTime.now(),
            ),
          );
    } catch (e, stackTrace) {
      // Dart's dart:developer log — the SDK's own low-ceremony choice
      // for "record this without pulling in a logging framework," which
      // this project doesn't otherwise have one of. Mirrors the
      // backend's logger.error(..., exc_info=True) intent: capture the
      // failure with its stack trace, but never let it propagate.
      developer.log(
        'Failed to write audit log (action=$action module=$module)',
        name: 'fulus.audit',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<AuditLogEntry>> getAuditLogs({
    required AuthRole requestingRole,
    String? module,
    String? userId,
    int page = 1,
    int pageSize = 50,
  }) async {
    // The local check IS the real enforcement now — see
    // AuthFailure.forbidden's doc comment in failure.dart. Takes the
    // caller's role as a parameter rather than looking it up via
    // AuthRepository itself — see this interface's own doc comment on
    // why (breaking a genuine circular dependency with
    // AuthRepositoryImpl, which depends on AuditRepository to log
    // login/logout/account-creation events).
    if (requestingRole != AuthRole.owner) {
      throw const AuthFailure.forbidden();
    }

    final query = _db.select(_db.auditLogs);
    if (module != null) {
      query.where((t) => t.module.equals(module));
    }
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    query
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(pageSize, offset: (page - 1) * pageSize);

    final rows = await query.get();
    return rows.map(_toEntry).toList();
  }

  AuditLogEntry _toEntry(AuditLogRow row) => AuditLogEntry(
        id: row.localId,
        userId: row.userId,
        action: row.action,
        module: row.module,
        recordId: row.recordId,
        details: row.details != null
            ? jsonDecode(row.details!) as Map<String, dynamic>
            : null,
        createdAt: row.createdAt,
      );
}
