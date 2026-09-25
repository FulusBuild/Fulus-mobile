import '../repositories/auth_repository.dart';
import '../repositories/location_repository.dart';

/// Performs a validated, serialized active-location switch.
///
/// A location switch only changes the session's active context. It never
/// mutates, rewrites, or rebinds existing business mutations; those already
/// carry their durable location identity in their own rows/outbox records.
class SwitchActiveLocation {
  SwitchActiveLocation({
    required LocationRepository locationRepository,
    required AuthRepository authRepository,
  })  : _locationRepository = locationRepository,
        _authRepository = authRepository;

  final LocationRepository _locationRepository;
  final AuthRepository _authRepository;

  Future<void>? _pending;

  Future<String> call(String locationId) {
    final request = (_pending ?? Future<void>.value()).then((_) async {
      final requested = locationId.trim();
      if (requested.isEmpty) {
        throw ArgumentError.value(locationId, 'locationId', 'must not be empty');
      }

      final location = await _locationRepository.getLocationById(requested);
      if (location == null) {
        throw StateError(
          'That location is not available on this device. '
          'Connect and sync locations before switching to it.',
        );
      }
      if (location.deletedAt != null) {
        throw StateError('That location is no longer available.');
      }

      final current = await _authRepository.getActiveLocationId();
      if (current == requested) return;

      await _authRepository.setActiveLocationId(requested);
    });

    _pending = request.then<void>((_) {}, onError: (_, __) {});
    return request.then((_) => locationId.trim());
  }
}
