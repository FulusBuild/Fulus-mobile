/// Compile-time environment configuration — Architecture Section 1 lists
/// "Environment configuration" as its own concern under Project Setup.
/// Uses Dart's built-in String.fromEnvironment (populated via
/// --dart-define at build/run time) rather than a new package
/// dependency for something this simple.
///
/// The default below is NOT "a real backend" — it's the Android
/// emulator's own alias for host localhost, which only ever resolves to
/// something real on a dev machine already running the backend. It is
/// deliberately never a pointer at any deployed environment, staging or
/// otherwise, per the brief's rule against hardcoded business data.
///
/// Usage:
///   flutter run --dart-define=API_BASE_URL=https://staging.example.com
///   flutter build apk --dart-define=API_BASE_URL=https://api.example.com
class EnvConfig {
  const EnvConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
