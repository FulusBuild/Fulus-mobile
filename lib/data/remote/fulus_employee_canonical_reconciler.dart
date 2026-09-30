import '../../domain/repositories/employee_repository.dart';
import 'fulus_sync_api.dart';

class FulusEmployeeCanonicalReconciler {
  FulusEmployeeCanonicalReconciler({required EmployeeRepository repository}) : _repository = repository;
  final EmployeeRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'employee') throw StateError('Employee canonical reconciler received an unexpected entity.');
    if (response.operation == 'delete') { await _repository.reconcileDeleted(response.entityId); return; }
    if (response.operation != 'upsert') throw StateError('Unsupported employee canonical operation.');
    final raw = response.data['row'];
    if (raw is! Map) throw StateError('Employee canonical response is missing row data.');
    final row = Map<String, dynamic>.from(raw);
    double? number(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    await _repository.reconcileServerState(
      serverId: response.entityId, membershipId: row['membership_id']?.toString(),
      cloudUserId: row['auth_user_id']?.toString(), fullName: row['full_name']?.toString() ?? '',
      role: row['role']?.toString(), department: row['department']?.toString(),
      position: row['position']?.toString(), salary: number(row['salary']),
      phone: row['phone']?.toString(), email: row['email']?.toString(),
      dateHired: date(row['date_hired']), locationId: row['location_id']?.toString(),
      isActive: row['is_active'] != false, createdAt: date(row['created_at']) ?? DateTime.now(),
      updatedAt: date(row['updated_at']) ?? DateTime.now(),
    );
  }
}