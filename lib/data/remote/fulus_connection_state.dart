import 'package:flutter/foundation.dart';

import 'fulus_business_context.dart';
import 'fulus_device_registration.dart';
import 'fulus_staff_access_api.dart';

/// Reactive connection state for the optional Fulus cloud backend.
///
/// Local authentication and local data never depend on this object. A null
/// business means cloud sync is unavailable; it is not an error condition.
class FulusConnectionState extends ChangeNotifier {
  FulusConnectionState({
    required FulusBusinessContext businessContext,
    required FulusDeviceRegistration deviceRegistration,
    FulusStaffAccessApi? staffAccessApi,
  })  : _businessContext = businessContext,
        _deviceRegistration = deviceRegistration,
        _staffAccessApi = staffAccessApi;

  final FulusBusinessContext _businessContext;
  final FulusDeviceRegistration _deviceRegistration;
  final FulusStaffAccessApi? _staffAccessApi;
  FulusRegisteredDevice? _registeredDevice;
  FulusMembershipContext? _membershipContext;
  String? _selectedBusinessId;
  bool _loading = false;

  FulusMembershipContext? get membershipContext => _membershipContext;
  String? get selectedBusinessId => _selectedBusinessId;
  bool get isLoading => _loading;
  FulusRegisteredDevice? get registeredDevice => _registeredDevice;
  bool get isDeviceAuthorized => _registeredDevice?.status == 'active';

  bool get isConnected =>
      _selectedBusinessId != null && _selectedBusinessId!.isNotEmpty;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final context = await _businessContext.fetch();
      _membershipContext = context;
      final active = context.memberships.where((m) => m.status == 'active');
      if (_selectedBusinessId == null ||
          !active.any((m) => m.businessId == _selectedBusinessId)) {
        _selectedBusinessId = active.length == 1 ? active.first.businessId : null;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<FulusRegisteredDevice> registerDevice({
    required String deviceClientId,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    final businessId = _selectedBusinessId;
    if (businessId == null) {
      throw StateError('Select an active business before registering the device.');
    }
    final device = await _deviceRegistration.register(
      businessId: businessId,
      deviceClientId: deviceClientId,
      deviceName: deviceName,
      platform: platform,
      appVersion: appVersion,
    );
    _registeredDevice = device;
    notifyListeners();
    return device;
  }

  Future<StaffInvite> createStaffInvite({
    required String roleId,
    String? email,
    int expiresHours = 24,
  }) async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) {
      throw StateError('Fulus cloud staff access is unavailable.');
    }
    return api.createInvite(
      businessId: businessId,
      roleId: roleId,
      email: email,
      expiresHours: expiresHours,
    );
  }

  Future<StaffClaim> claimStaffInvite(String token) async {
    final api = _staffAccessApi;
    if (api == null) throw StateError('Fulus cloud staff access is unavailable.');
    final claim = await api.claimInvite(token);
    await refresh();
    selectBusiness(claim.businessId);
    return claim;
  }

  Future<bool> setStaffStatus({required String membershipId, required String status}) async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) throw StateError('Fulus cloud staff access is unavailable.');
    final changed = await api.setMemberStatus(businessId: businessId, membershipId: membershipId, status: status);
    if (changed) await refresh();
    return changed;
  }

  Future<bool> changeStaffRole({required String membershipId, required String roleId}) async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) throw StateError('Fulus cloud staff access is unavailable.');
    final changed = await api.changeMemberRole(businessId: businessId, membershipId: membershipId, roleId: roleId);
    if (changed) await refresh();
    return changed;
  }

  Future<bool> setStaffRolePermission({required String roleId, required String permissionId, required bool enabled}) async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) throw StateError('Fulus cloud staff access is unavailable.');
    return api.setRolePermission(businessId: businessId, roleId: roleId, permissionId: permissionId, enabled: enabled);
  }

  Future<List<FulusDevice>> listStaffDevices() async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) throw StateError('Fulus cloud staff access is unavailable.');
    return api.listDevices(businessId);
  }

  Future<bool> revokeStaffDevice(String deviceId) async {
    final api = _staffAccessApi;
    final businessId = _selectedBusinessId;
    if (api == null || businessId == null) throw StateError('Fulus cloud staff access is unavailable.');
    final revoked = await api.revokeDevice(businessId: businessId, deviceId: deviceId);
    if (revoked && _registeredDevice?.id == deviceId) _registeredDevice = null;
    notifyListeners();
    return revoked;
  }

  void selectBusiness(String businessId) {
    final allowed = _membershipContext?.memberships.any(
          (m) => m.businessId == businessId && m.status == 'active',
        ) ??
        false;
    if (!allowed) {
      throw ArgumentError('Business is not an active server membership.');
    }
    if (_selectedBusinessId == businessId) return;
    _selectedBusinessId = businessId;
    _registeredDevice = null;
    notifyListeners();
  }

  void disconnect() {
    if (_selectedBusinessId == null && _registeredDevice == null) return;
    _selectedBusinessId = null;
    _registeredDevice = null;
    notifyListeners();
  }
}
