/// Public configuration for the optional Fulus cloud connection.
/// The publishable Supabase key is intentionally not a secret; it is safe
/// to ship in a client application. Override both values at build time
/// for staging/dev without changing source.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bejcuvoxemwomcatgyxz.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_POaHTyngxKH1wEfo9q7v2Q_ddDPrI80',
  );

  static const String functionBaseUrl = String.fromEnvironment(
    'FULUS_FUNCTION_BASE_URL',
    defaultValue: 'https://bejcuvoxemwomcatgyxz.supabase.co/functions/v1/fulus-api',
  );

  static const String businessProvisionFunctionUrl = String.fromEnvironment(
    'FULUS_BUSINESS_PROVISION_FUNCTION_URL',
    defaultValue: 'https://bejcuvoxemwomcatgyxz.supabase.co/functions/v1/fulus-provision-business',
  );
}
