import '../../core/money/money.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../../data/local/database/database.dart';
import '../sync_handler.dart';

class EmployeeSyncHandler implements SyncHandler {
  EmployeeSyncHandler({
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required EmployeeRepository employeeRepository,
    required LocationRepository locationRepository,
  })  : _api = fulusSyncApi,
        _connection = fulusConnectionState,
        _repository = employeeRepository,
        _locationRepository = locationRepository;

  final FulusSyncApi _api;
  final FulusConnectionState _connection;
  final EmployeeRepository _repository;
  final LocationRepository _locationRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create' && item.operation != 'update') {
      throw StateError('EmployeeSyncHandler does not support this operation.');
    }
    final employee = await _repository.getEmployeeById(
      item.entityLocalId,
      includeInactive: true,
      forSync: true,
    );
    if (employee == null) throw StateError('No local employee found.');
    final businessId = _connection.selectedBusinessId;
    final device = _connection.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for employee sync.');
    }
    final isUpdate = item.operation == 'update';
    String? cloudLocationId;
    if (employee.locationId != null) {
      final location = await _locationRepository.getLocationById(employee.locationId!);
      if (location == null) throw StateError('Employee location is no longer available on this device.');
      cloudLocationId = location.serverId;
      if (cloudLocationId == null || cloudLocationId.isEmpty) {
        throw StateError('Employee location has not finished syncing yet.');
      }
    }
    if (isUpdate && (employee.serverId == null || employee.serverId!.isEmpty)) {
      throw StateError('Cannot sync employee update before its create has synced.');
    }
    final result = await _api.submitOperation(
      businessId: businessId,
      operationType: isUpdate ? 'employee.update' : 'employee.create',
      operationId: item.id,
      clientReference: employee.id,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId, 'operation_id': item.id, 'client_reference': employee.id,
        'full_name': employee.fullName, 'role': employee.role, 'department': employee.department,
        'position': employee.position, 'salary': employee.salary == null ? null : moneyToWire(employee.salary!), 'phone': employee.phone,
        'email': employee.email, 'date_hired': employee.dateHired?.toIso8601String(),
        'location_id': cloudLocationId, 'is_active': employee.isActive,
        if (isUpdate) 'server_id': employee.serverId,
        if (isUpdate && item.baseCursor != null) 'base_cursor': item.baseCursor,
      },
    );
    final raw = result['data'];
    if (raw is! Map) throw StateError('Fulus employee sync returned no response data.');
    final data = Map<String, dynamic>.from(raw);
    final serverId = (data['entity_id'] ?? data['employee_id'])?.toString();
    if (serverId == null || serverId.isEmpty) throw StateError('Fulus employee sync returned no server entity ID.');
    final employeeRow = data['employee'];
    final row = employeeRow is Map ? Map<String, dynamic>.from(employeeRow) : const <String, dynamic>{};
    await _repository.markSynced(
      localId: employee.id, serverId: serverId,
      membershipId: row['membership_id']?.toString(),
      cloudUserId: row['auth_user_id']?.toString(), operationId: item.id,
    );
  }
}