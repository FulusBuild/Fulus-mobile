import 'package:flutter/foundation.dart';

import 'fulus_business_context.dart';

/// Reactive connection state for the optional Fulus cloud backend.
///
/// Local authentication and local data never depend on this object. A null
/// business means cloud sync is unavailable; it is not an error condition.
class FulusConnectionState extends ChangeNotifier {
  FulusConnectionState({required FulusBusinessContext businessContext})
      : _businessContext = businessContext;

  final FulusBusinessContext _businessContext;
  FulusMembershipContext? _membershipContext;
  String? _selectedBusinessId;
  bool _loading = false;

  FulusMembershipContext? get membershipContext => _membershipContext;
  String? get selectedBusinessId => _selectedBusinessId;
  bool get isLoading => _loading;
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
    notifyListeners();
  }

  void disconnect() {
    if (_selectedBusinessId == null) return;
    _selectedBusinessId = null;
    notifyListeners();
  }
}
