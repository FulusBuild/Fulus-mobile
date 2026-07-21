import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/endpoints/auth_api.dart';
import '../data/remote/endpoints/sales_api.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../sync/handlers/sale_sync_handler.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_triggers.dart';
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
      // A placeholder ONLY for the brief window between this
      // constructor call and authRepository existing a few lines below
      // — apiClient.setOnSessionExpired(...) further down replaces this
      // with the real callback before bootstrap() returns. Never
      // actually reachable in practice: nothing here awaits a network
      // call between this line and that reassignment.
    },
  );

  final authApi = AuthApi(apiClient);
  final authRepository = AuthRepositoryImpl(
    authApi: authApi,
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  // Architecture Section 6: "attempt a silent refresh using the stored
  // refresh token before showing any login screen at all" — awaited
  // here, before bootstrap() returns, so main.dart's runApp never shows
  // a blank/loading state for this. A missing or invalid stored refresh
  // token resolves to null quickly (no network call at all in the
  // former case) rather than hanging; see restoreSession's own comment
  // on why a network failure specifically does NOT clear the stored
  // token even though it also returns null.
  await authRepository.restoreSession();

  // Reusing logout() here (rather than a separate method) is
  // deliberate, not a loose fit: by the time onSessionExpired fires,
  // the interceptor has already tried and failed to refresh, so
  // logout()'s own best-effort call to POST /api/auth/logout will fail
  // too (no valid access token left to authenticate it) — which is
  // fine, since that call is wrapped in its own try/catch specifically
  // because a failed audit-log ping must never block clearing the
  // local session.
  apiClient.setOnSessionExpired(() => authRepository.logout());

  final salesApi = SalesApi(apiClient);
  final syncQueue = SyncQueue(database);
  final saleRepository = SaleRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );

  // The rest of the sync engine graph builds on top of saleRepository,
  // which itself depends on syncQueue above — constructing SyncTriggers
  // (or SyncEngine) before saleRepository exists isn't possible, hence
  // the setOnEnqueued call at the end rather than passing this into
  // SyncQueue's constructor (see sync_queue.dart's own comment on
  // exactly why this would otherwise be a construction-order cycle).
  final saleSyncHandler = SaleSyncHandler(
    db: database,
    salesApi: salesApi,
    saleRepository: saleRepository,
  );
  final syncEngine = SyncEngine(
    db: database,
    handlersByEntityType: {'sale': saleSyncHandler},
  );
  final syncTriggers = SyncTriggers(syncEngine: syncEngine);
  await syncTriggers.start();

  syncQueue.setOnEnqueued(syncTriggers.notifyEnqueued);

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      secureStorageProvider.overrideWithValue(secureStorage),
      apiClientProvider.overrideWithValue(apiClient),
      authApiProvider.overrideWithValue(authApi),
      authRepositoryProvider.overrideWithValue(authRepository),
      salesApiProvider.overrideWithValue(salesApi),
      syncQueueProvider.overrideWithValue(syncQueue),
      saleRepositoryProvider.overrideWithValue(saleRepository),
      syncEngineProvider.overrideWithValue(syncEngine),
      syncTriggersProvider.overrideWithValue(syncTriggers),
    ],
  );

  return container;
}
