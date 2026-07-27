import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../core/security/pin_hasher.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/endpoints/auth_api.dart';
import '../data/remote/endpoints/business_settings_api.dart';
import '../data/remote/endpoints/customers_api.dart';
import '../data/remote/endpoints/expenses_api.dart';
import '../data/remote/endpoints/income_api.dart';
import '../data/remote/endpoints/locations_api.dart';
import '../data/remote/endpoints/products_api.dart';
import '../data/remote/endpoints/sales_api.dart';
import '../data/remote/endpoints/stock_movements_api.dart';
import '../data/repositories/approval_pin_repository_impl.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/business_settings_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/expense_repository_impl.dart';
import '../data/repositories/income_record_repository_impl.dart';
import '../data/repositories/location_repository_impl.dart';
import '../data/repositories/product_repository_impl.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../data/repositories/stock_movement_repository_impl.dart';
import '../sync/handlers/customer_sync_handler.dart';
import '../sync/handlers/expense_sync_handler.dart';
import '../sync/handlers/income_sync_handler.dart';
import '../sync/handlers/sale_sync_handler.dart';
import '../sync/handlers/stock_movement_sync_handler.dart';
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

  final approvalPinRepository = ApprovalPinRepositoryImpl(
    authApi: authApi,
    secureStorage: secureStorage,
    pinHasher: const Argon2PinHasher(),
  );

  final salesApi = SalesApi(apiClient);
  final customersApi = CustomersApi(apiClient);
  final expensesApi = ExpensesApi(apiClient);
  final incomeApi = IncomeApi(apiClient);
  final stockMovementsApi = StockMovementsApi(apiClient);
  final productsApi = ProductsApi(apiClient);
  final locationsApi = LocationsApi(apiClient);
  final businessSettingsApi = BusinessSettingsApi(apiClient);
  final syncQueue = SyncQueue(database);
  final saleRepository = SaleRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final customerRepository = CustomerRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final expenseRepository = ExpenseRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final incomeRecordRepository = IncomeRecordRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final stockMovementRepository = StockMovementRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  // No syncQueue dependency — Product is read + pull-sync only (see its
  // repository interface's own doc comment), nothing about it goes
  // through the push-oriented SyncQueue/SyncEngine machinery the other
  // five repositories above all do.
  final productRepository = ProductRepositoryImpl(
    db: database,
    productsApi: productsApi,
  );
  // Same shape as productRepository above, for the same reason —
  // LocationRepository's own doc comment: read + pull-sync only,
  // deliberately no create/update method.
  final locationRepository = LocationRepositoryImpl(
    db: database,
    locationsApi: locationsApi,
  );
  // Same shape again — BusinessSettingsRepository's own doc comment:
  // read + pull-sync only, matching the backend's BusinessProfile
  // having no create/update path from mobile either.
  final businessSettingsRepository = BusinessSettingsRepositoryImpl(
    db: database,
    businessSettingsApi: businessSettingsApi,
  );

  // Phase 0's own long-open question, decided here once for all three
  // read + pull-sync entities together (per the checkpoint notes: "worth
  // deciding that trigger mechanism ONCE, for all three together, rather
  // than three separate times") — on launch, fire-and-forget. Not
  // awaited before bootstrap() returns, unlike authRepository
  // .restoreSession() above: a slow or failed initial catalog sync must
  // never delay or block app startup, since that's exactly the "must
  // work offline" requirement this whole project exists to satisfy — a
  // fresh launch with no signal should still open straight to whatever
  // was already cached locally, not hang waiting on these. ApiClient's
  // own bounded Dio timeouts (connectTimeout 10s, receiveTimeout 15s —
  // api_client.dart) mean a no-connectivity launch fails each of these
  // within a bounded window rather than hanging forever in the
  // background either, so no separate connectivity pre-check is needed
  // here the way SyncTriggers._runIfOnline has one — that check exists
  // to avoid repeated doomed attempts on frequent triggers (every
  // connectivity change, every app resume); this runs exactly once, at
  // launch, and each of the three is independent of the other two
  // (a slow Product catalog pull must not delay Location or
  // BusinessSettings from completing, hence three separate calls here
  // rather than one that awaits all three in sequence).
  //
  // What this deliberately does NOT solve: a fresh install's very first
  // launch with zero connectivity has no cached Location/Product data to
  // fall back to regardless of what runs here — that's a real,
  // separate onboarding-UX gap (the Product Design Bible's eventual
  // "waiting for setup" treatment), not something built as part of
  // choosing this trigger.
  unawaited(locationRepository.syncFromServer().catchError((_) {}));
  unawaited(businessSettingsRepository.syncFromServer().catchError((_) {}));
  unawaited(productRepository.syncFromServer().catchError((_) {}));

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
  final customerSyncHandler = CustomerSyncHandler(
    customersApi: customersApi,
    customerRepository: customerRepository,
  );
  final expenseSyncHandler = ExpenseSyncHandler(
    expensesApi: expensesApi,
    expenseRepository: expenseRepository,
  );
  final incomeSyncHandler = IncomeSyncHandler(
    incomeApi: incomeApi,
    incomeRecordRepository: incomeRecordRepository,
  );
  final stockMovementSyncHandler = StockMovementSyncHandler(
    db: database,
    stockMovementsApi: stockMovementsApi,
    stockMovementRepository: stockMovementRepository,
    productRepository: productRepository,
  );
  final syncEngine = SyncEngine(
    db: database,
    handlersByEntityType: {
      'sale': saleSyncHandler,
      'customer': customerSyncHandler,
      'expense': expenseSyncHandler,
      'income_record': incomeSyncHandler,
      'stock_movement': stockMovementSyncHandler,
    },
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
      approvalPinRepositoryProvider.overrideWithValue(approvalPinRepository),
      salesApiProvider.overrideWithValue(salesApi),
      customersApiProvider.overrideWithValue(customersApi),
      expensesApiProvider.overrideWithValue(expensesApi),
      syncQueueProvider.overrideWithValue(syncQueue),
      saleRepositoryProvider.overrideWithValue(saleRepository),
      customerRepositoryProvider.overrideWithValue(customerRepository),
      expenseRepositoryProvider.overrideWithValue(expenseRepository),
      incomeApiProvider.overrideWithValue(incomeApi),
      incomeRecordRepositoryProvider.overrideWithValue(incomeRecordRepository),
      stockMovementsApiProvider.overrideWithValue(stockMovementsApi),
      stockMovementRepositoryProvider.overrideWithValue(stockMovementRepository),
      productsApiProvider.overrideWithValue(productsApi),
      productRepositoryProvider.overrideWithValue(productRepository),
      locationsApiProvider.overrideWithValue(locationsApi),
      locationRepositoryProvider.overrideWithValue(locationRepository),
      businessSettingsApiProvider.overrideWithValue(businessSettingsApi),
      businessSettingsRepositoryProvider.overrideWithValue(businessSettingsRepository),
      syncEngineProvider.overrideWithValue(syncEngine),
      syncTriggersProvider.overrideWithValue(syncTriggers),
    ],
  );

  return container;
}
