import 'package:flutter/foundation.dart';

import 'fulus_business_context.dart';
import 'fulus_device_registration.dart';

/// Reactive connection state for the optional Fulus cloud backend.
///
/// Local authentication and local data never depend on this object. A null
/// business means cloud sync is unavailable; it is not an error condition.
class FulusConnectionState extends ChangeNotifier {
  FulusConnectionState({
    required FulusBusinessContext businessContext,
    required FulusDeviceRegistration deviceRegistration,
  })  : _businessContext = businessContext,
        _deviceRegistration = deviceRegistration;

  final FulusBusinessContext _businessContext;
  final FulusDeviceRegistration _deviceRegistration;
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
    if (_selectedBusinessId == null) return;
    _selectedBusinessId = null;
    notifyListeners();
  }
}
