import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/endpoints/sales_api.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../sync/sync_queue.dart';
import 'providers.dart';

/// Wires the app's real dependencies together and returns a
/// ProviderContainer with them overridden in — per Architecture Section
/// 1's stated split, this is where DI actually happens, not main.dart,
/// and it's what makes main.dart's `await bootstrap()` call (already
/// written, before this file existed) resolve to something real.
///
/// Order matters here and is deliberate, not incidental: the database
/// opens first because everything else (secure storage doesn't depend on
/// it, but the eventual repository layer does) should be able to assume
/// it's ready; the ApiClient is constructed last because it needs
/// SecureStorage already built to hand it the token-refresh callback.
Future<ProviderContainer> bootstrap() async {
  // AppDatabase.open() uses LazyDatabase internally (see database.dart) —
  // the actual file I/O is deferred until the first query, not blocking
  // here, but the object itself is real and ready to be depended on by
  // the time this function returns.
  final database = AppDatabase.open();

  final secureStorage = SecureStorage();

  // Read from EnvConfig (core/config/env_config.dart) — see that file
  // for how to override at build/run time via --dart-define. No longer
  // a hardcoded literal in this function.
  const baseUrl = EnvConfig.apiBaseUrl;

  late final ApiClient apiClient;
  apiClient = ApiClient(
    baseUrl: baseUrl,
    secureStorage: secureStorage,
    onSessionExpired: () async {
      // Called by the auth interceptor when a refresh genuinely fails
      // (Architecture Section 6). What this needs to DO — clear the
      // in-memory session state, route to login — depends on the auth
      // state provider, which is itself part of this same DI graph and
      // hasn't been written yet in this phase. Left as a documented,
      // explicit no-op rather than a silent one, so it's not mistaken
      // for a finished implementation.
      // TODO(auth-phase): clear session provider state and trigger
      // navigation to login once the auth state provider exists.
    },
  );

  final salesApi = SalesApi(apiClient);
  final syncQueue = SyncQueue(database);
  final saleRepository = SaleRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      secureStorageProvider.overrideWithValue(secureStorage),
      apiClientProvider.overrideWithValue(apiClient),
      salesApiProvider.overrideWithValue(salesApi),
      syncQueueProvider.overrideWithValue(syncQueue),
      saleRepositoryProvider.overrideWithValue(saleRepository),
    ],
  );

  return container;
}
