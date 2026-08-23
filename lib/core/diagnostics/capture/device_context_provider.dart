import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/device_context.dart';

/// Resolves [DeviceContext] once, at startup, and caches it for the
/// rest of the process — both `PackageInfo.fromPlatform()` and
/// `DeviceInfoPlugin().androidInfo` cross a platform channel, which is
/// unnecessary work to repeat on every single captured event.
///
/// Android-only, matching this project (no `ios/` platform folder
/// exists — verified directly rather than assumed).
///
/// Resolution is `await`ed once during bootstrap, before the app is
/// considered fully started (see bootstrap.dart) — by the time real
/// user-triggered errors are possible, [current] is already populated.
/// If resolution itself fails (a platform-channel error on a very odd
/// device), [current] simply stays [DeviceContext.unknown] rather than
/// that failure blocking startup — device metadata is enrichment, never
/// a precondition for the diagnostic system, or anything else, to work.
class DeviceContextProvider {
  DeviceContext _current = const DeviceContext.unknown();

  DeviceContext get current => _current;

  Future<void> resolve() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      String deviceModel = 'unknown';
      String osVersion = 'unknown';
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final manufacturer = androidInfo.manufacturer.trim();
        final model = androidInfo.model.trim();
        deviceModel = manufacturer.isEmpty
            ? model
            : (model.toLowerCase().startsWith(manufacturer.toLowerCase())
                ? model
                : '$manufacturer $model');
        osVersion = 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
      } catch (_) {
        // Device-specific info is the more failure-prone half of this
        // (device_info_plus reads real OEM-provided system properties,
        // which are occasionally missing or malformed on obscure
        // hardware) — app version/build below still gets recorded even
        // if this inner block fails.
      }
      _current = DeviceContext(
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        deviceModel: deviceModel,
        osName: 'Android',
        osVersion: osVersion,
      );
    } catch (_) {
      // Leaves _current at DeviceContext.unknown() — see this class's
      // own header comment on why that's an acceptable outcome, not an
      // error worth surfacing.
    }
  }
}
