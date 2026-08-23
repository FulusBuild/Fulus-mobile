/// App version, build, and device/OS facts attached to every
/// [DiagnosticEvent] — resolved once at startup by
/// `DeviceContextProvider` (capture/device_context_provider.dart) and
/// then reused for every event captured in this session, rather than
/// re-queried per event (`package_info_plus`/`device_info_plus` both
/// cross a platform channel, which is unnecessary work to repeat on
/// every single capture).
///
/// [DeviceContext.unknown] exists specifically for the window between
/// process start and the first successful platform-channel resolution
/// (or for the rare case that resolution fails entirely) — an event
/// captured in that window still gets a real record, just with these
/// fields honestly blank rather than the capture itself waiting on a
/// value that may never arrive. See device_context_provider.dart.
class DeviceContext {
  const DeviceContext({
    required this.appVersion,
    required this.buildNumber,
    required this.deviceModel,
    required this.osName,
    required this.osVersion,
  });

  const DeviceContext.unknown()
      : appVersion = 'unknown',
        buildNumber = 'unknown',
        deviceModel = 'unknown',
        osName = 'Android',
        osVersion = 'unknown';

  /// pubspec.yaml's `version` field, the part before the `+`.
  final String appVersion;

  /// pubspec.yaml's `version` field, the part after the `+`.
  final String buildNumber;

  /// e.g. "Tecno Spark 10" — manufacturer + model, the two fields most
  /// useful for spotting a device-specific pattern across several
  /// reports (a business chain running the same handset model at every
  /// till, say).
  final String deviceModel;

  final String osName;

  /// e.g. Android's own release string ("13") plus SDK level, combined
  /// — both are useful: the release string is what a person recognizes,
  /// the SDK level is what actually gates API availability.
  final String osVersion;

  Map<String, Object?> toJson() => {
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'deviceModel': deviceModel,
        'osName': osName,
        'osVersion': osVersion,
      };

  factory DeviceContext.fromJson(Map<String, Object?> json) => DeviceContext(
        appVersion: json['appVersion'] as String? ?? 'unknown',
        buildNumber: json['buildNumber'] as String? ?? 'unknown',
        deviceModel: json['deviceModel'] as String? ?? 'unknown',
        osName: json['osName'] as String? ?? 'Android',
        osVersion: json['osVersion'] as String? ?? 'unknown',
      );
}
