import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../core/config/supabase_config.dart';
import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/storage/drift_diagnostic_store.dart';
import '../core/export/export_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/onboarding/onboarding_state.dart';
import '../core/security/pin_hasher.dart';
import '../data/local/database/app_database_lifecycle.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/fulus_business_context.dart';
import '../data/remote/fulus_connection_state.dart';
import '../data/remote/fulus_device_registration.dart';
import '../data/remote/endpoints/auth_api.dart';
import '../data/remote/endpoints/business_settings_api.dart';
import '../data/remote/endpoints/cash_drawer_shifts_api.dart';
import '../data/remote/endpoints/categories_api.dart';
import '../data/remote/endpoints/customers_api.dart';
import '../data/remote/endpoints/expense_categories_api.dart';
import '../data/remote/endpoints/expenses_api.dart';
import '../data/remote/endpoints/income_api.dart';
import '../data/remote/endpoints/locations_api.dart';
import '../data/remote/endpoints/products_api.dart';
import '../data/remote/endpoints/returns_api.dart';
import '../data/remote/endpoints/sales_api.dart';
import '../data/remote/endpoints/stock_movements_api.dart';
import '../data/remote/endpoints/suppliers_api.dart';
import '../data/repositories/approval_pin_repository_impl.dart';
import '../data/repositories/audit_repository_impl.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/backup_repository_impl.dart';
import '../data/repositories/business_settings_repository_impl.dart';
import '../data/repositories/cash_drawer_shift_repository_impl.dart';
import '../data/repositories/category_repository_impl.dart';
import '../data/repositories/customer_credit_repository_impl.dart';
import '../data/repositories/customer_repository_impl.dart';
import '../data/repositories/dashboard_repository_impl.dart';
import '../data/repositories/draft_cart_repository_impl.dart';
import '../data/repositories/employee_repository_impl.dart';
import '../data/repositories/expense_category_repository_impl.dart';
import '../data/repositories/expense_repository_impl.dart';
import '../data/repositories/finance_stats_repository_impl.dart';
import '../data/repositories/income_record_repository_impl.dart';
import '../data/repositories/location_repository_impl.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../data/repositories/permission_repository_impl.dart';
import '../data/repositories/printer_repository_impl.dart';
import '../data/repositories/product_repository_impl.dart';
import '../data/repositories/receipt_repository_impl.dart';
import '../data/repositories/reports_repository_impl.dart';
import '../data/repositories/return_repository_impl.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../data/repositories/search_repository_impl.dart';
import '../data/repositories/stock_movement_repository_impl.dart';
import '../data/repositories/supplier_credit_repository_impl.dart';
import '../data/repositories/supplier_repository_impl.dart';
import '../data/repositories/tax_remittance_repository_impl.dart';
import '../device_services/camera/camera_service.dart';
import '../device_services/printing/printer_discovery_service.dart';
import '../device_services/printing/receipt_printer_service.dart';
import '../device_services/scanning/barcode_scanner_service.dart';
import '../domain/usecases/active_location_resolver.dart';
import '../domain/usecases/global_search.dart';
import '../domain/usecases/import_products_from_csv.dart';
import '../sync/handlers/category_sync_handler.dart';
import '../sync/handlers/cash_drawer_shift_sync_handler.dart';
import '../sync/handlers/customer_sync_handler.dart';
import '../sync/handlers/expense_category_sync_handler.dart';
import '../sync/handlers/expense_sync_handler.dart';
import '../sync/handlers/income_sync_handler.dart';
import '../sync/handlers/location_sync_handler.dart';
import '../sync/handlers/product_sync_handler.dart';
import '../sync/handlers/return_sync_handler.dart';
import '../sync/handlers/sale_sync_handler.dart';
import '../sync/handlers/stock_movement_sync_handler.dart';
import '../sync/handlers/supplier_sync_handler.dart';
import '../sync/sync_config.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_status_notifier.dart';
import '../sync/sync_triggers.dart';
import 'providers.dart';

/// Wires the app's real dependencies together and returns a
/// ProviderContainer with them overridden in — per Architecture Section
/// 1's stated split, this is where DI actually happens, not main.dart,
/// and it's what makes main.dart's `await bootstrap()` call (already
/// written, before this file existed) resolve to something real.
///
/// Order matters here and is deliberate, not incidental: the database
/// opens first because the repository layer depends on it being ready.
///
/// ApiClient/AuthApi are constructed unconditionally, not gated behind
/// SyncConfig: constructing a Dio instance makes no network call by
/// itself (see ApiClient's own doc comment), and
/// ApprovalPinRepositoryImpl's push/pull still uses AuthApi regardless
/// of the general sync toggle — an owner's approval-PIN sync is a
/// narrower, separate concern from bulk catalog/settings sync. What
/// SyncConfig actually gates: the three read-repository pull-sync calls
/// below, and (inside sync_triggers.dart itself) every path that would
/// start the sync engine or touch the network on an ongoing basis.
Future<ProviderContainer> bootstrap({required DiagnosticLogger diagnosticLogger}) async {
  // AppDatabase.open() uses LazyDatabase internally (see database.dart) —
  // the actual file I/O is deferred until the first query, not blocking
  // here, but the object itself is real and ready to be depended on by
  // the time this function returns.
  //
  // `var`, not `final`: AppDatabaseLifecycle needs to be able to swap
  // this to a freshly-reopened instance after a restore closes the
  // original connection — see that class's own doc comment for exactly
  // what this does and does not achieve regarding the repositories
  // constructed below, which capture today's value directly and are NOT
  // retroactively updated by a later reassignment here.
  var database = AppDatabase.open();

  // Diagnostic & Crash Logging System: attached as early as possible,
  // right after `database` exists — everything bootstrap() does from
  // this line on is now covered by real persistence rather than the
  // file-based fallback DiagnosticLogger's constructor already set it
  // up with (see main.dart's own comment on why diagnosticLogger is
  // constructed even earlier than this, before bootstrap() is called at
  // all). Retention cleanup runs once per cold start, fire-and-forget —
  // never worth delaying launch for housekeeping, and never worth a
  // dedicated WorkManager task for something this cheap.
  diagnosticLogger.attachStore(DriftDiagnosticStore(database));
  unawaited(diagnosticLogger.applyRetentionPolicy());

  final secureStorage = SecureStorage();

  // Loaded early, right alongside the other basic infra above, since it
  // gates several of the steps immediately below — see SyncConfig's own
  // doc comment for why this defaults to disabled and what that default
  // is actually claiming.
  final syncConfig = await SyncConfig.load();

  // Loaded early for the same reason as SyncConfig immediately above:
  // _ShellGate (router.dart) needs its value before the widget tree's
  // first real build.
  final onboardingState = await OnboardingState.load();

  // Read from EnvConfig (core/config/env_config.dart) — see that file
  // for how to override at build/run time via --dart-define. No longer
  // a hardcoded literal in this function.
  const baseUrl = EnvConfig.apiBaseUrl;

  late final ApiClient apiClient;
  apiClient = ApiClient(
    baseUrl: baseUrl,
    secureStorage: secureStorage,
    // Architecture Redesign: auth no longer has anything to do with
    // ApiClient at all — AuthRepositoryImpl below never calls
    // apiClient.setAccessToken, and there's no token for a 401 here to
    // mean "expired" in the old sense. ApiClient itself stays exactly as
    // it was for the one thing it's still genuinely needed for: the
    // optional, still-networked Sync layer (approval-hash sync today;
    // LAN/cloud sync later). This callback is left a permanent no-op
    // rather than wired to anything auth-related — what a 401 from a
    // future networked Host should actually mean is that layer's own
    // design question, not something this stage should guess at and
    // wire in speculatively.
    onSessionExpired: () async {},
  );

  final fulusFunctionBaseUrl = '${SupabaseConfig.url}/functions/v1/fulus-api';
  final fulusBusinessContext = FulusBusinessContext(
    client: apiClient,
    functionBaseUrl: fulusFunctionBaseUrl,
  );
  final fulusDeviceRegistration = FulusDeviceRegistration(
    client: apiClient,
    functionBaseUrl: fulusFunctionBaseUrl,
  );
  final fulusConnectionState = FulusConnectionState(
    businessContext: fulusBusinessContext,
    deviceRegistration: fulusDeviceRegistration,
  );

  final authApi = AuthApi(apiClient);

  // Optional cloud session restore is deliberately fire-and-forget: a cold
  // start must never wait on the network or make local Fulus unavailable.
  // If a refresh token exists, the session is restored in the background;
  // if it does not, nothing happens.
  unawaited(authApi.restoreServerSession(
    supabaseUrl: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  ));

  // Constructed before AuthRepositoryImpl on purpose: AuthRepositoryImpl
  // depends on AuditRepository (to log login/logout/account-creation
  // events), and AuditRepositoryImpl has no dependency on AuthRepository
  // at all — see AuditRepository.getAuditLogs' own doc comment on why
  // that asymmetry is deliberate, not an oversight; the reverse would
  // make the two impossible to construct.
  final auditRepository = AuditRepositoryImpl(db: database);

  // Constructed before AuthRepositoryImpl for the same reason as
  // auditRepository just above: AuthRepositoryImpl.createEmployeeAccount
  // depends on this (to seed a new login's starting permission grant),
  // and PermissionRepositoryImpl has no dependency back on AuthRepository
  // at all.
  final permissionRepository = PermissionRepositoryImpl(db: database);

  final authRepository = AuthRepositoryImpl(
    db: database,
    // Same Argon2PinHasher instance shape ApprovalPinRepositoryImpl
    // below already constructs — see AuthRepositoryImpl's own doc
    // comment for why local identities use a PIN, not a password, as
    // of the onboarding-simplification pass. Argon2PasswordHasher is no
    // longer wired in here at all; nothing in AuthRepositoryImpl calls
    // it anymore (see that class's doc comment for where it's still
    // needed instead).
    pinHasher: const Argon2PinHasher(),
    auditRepository: auditRepository,
    permissionRepository: permissionRepository,
  );

  // restoreSession() is a plain local Sessions + Users table lookup, no
  // network call at all, so awaiting it here costs nothing and there's
  // no "network failure" branch to reason about — it either finds a
  // valid local session or it doesn't.
  await authRepository.restoreSession();

  final approvalPinRepository = ApprovalPinRepositoryImpl(
    authApi: authApi,
    secureStorage: secureStorage,
    pinHasher: const Argon2PinHasher(),
    auditRepository: auditRepository,
  );

  final salesApi = SalesApi(apiClient);
  final customersApi = CustomersApi(apiClient);
  final expensesApi = ExpensesApi(apiClient);
  final expenseCategoriesApi = ExpenseCategoriesApi(apiClient);
  final incomeApi = IncomeApi(apiClient);
  final stockMovementsApi = StockMovementsApi(apiClient);
  final productsApi = ProductsApi(apiClient);
  final categoriesApi = CategoriesApi(apiClient);
  final suppliersApi = SuppliersApi(apiClient);
  final returnsApi = ReturnsApi(apiClient);
  final cashDrawerShiftsApi = CashDrawerShiftsApi(apiClient);
  final locationsApi = LocationsApi(apiClient);
  final businessSettingsApi = BusinessSettingsApi(apiClient);
  final syncQueue = SyncQueue(database);
  // Moved ahead of saleRepository (bug fix: business logic audit) —
  // SaleRepositoryImpl now needs this to record a credit sale's
  // outstanding balance at the moment the sale is created; only needs
  // `db`, so nothing else has to move to make room for it. See
  // customerCreditRepository's own original construction comment
  // further down for why it needs no syncQueue.
  final customerCreditRepository = CustomerCreditRepositoryImpl(db: database);
  final saleRepository = SaleRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    authRepository: authRepository,
    customerCreditRepository: customerCreditRepository,
    diagnosticLogger: diagnosticLogger,
    canSync: () async => fulusConnectionState.isConnected &&
        fulusConnectionState.isDeviceAuthorized,
  );
  final customerRepository = CustomerRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final expenseRepository = ExpenseRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    auditRepository: auditRepository,
  );
  final incomeRecordRepository = IncomeRecordRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final stockMovementRepository = StockMovementRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  // Product is no longer read + pull-sync only — createProduct/
  // updateProduct now push through the same SyncQueue/SyncEngine
  // machinery every other write-capable repository here does; see
  // ProductRepository's interface doc for the fuller reasoning.
  final productRepository = ProductRepositoryImpl(
    db: database,
    productsApi: productsApi,
    syncQueue: syncQueue,
  );
  // Category/Supplier/CustomerCredit/DraftCart/Return are grouped here
  // rather than interleaved individually above, since every one of them
  // needs at least productRepository (already constructed by this
  // point) and some need each other too — grouping keeps the dependency
  // order legible in one place instead of scattered.
  //
  // Category/Supplier — same push-sync shape as customerRepository
  // above (write-locally-then-enqueue), not productRepository's
  // pull-only one; see CategoryRepository/SupplierRepository's own doc
  // comments for why.
  final categoryRepository = CategoryRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  final supplierRepository = SupplierRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  // customerCreditRepository itself now constructed earlier, just above
  // saleRepository — see that construction's own comment. (No sync
  // queue at all, still true: every write path this repository has is
  // marked settled by convention today; see CustomerCreditRepository's
  // own doc comment and CustomerLedgerEntryType's per-variant reasoning
  // for exactly why.)
  // The cart-persistence layer — see DraftCartRepository's own doc
  // comment. Depends on both productRepository (price/name lookups when
  // adding a catalog item) and saleRepository (completeSale's bridge to
  // a real, synced Sale) — both already constructed above.
  final draftCartRepository = DraftCartRepositoryImpl(
    db: database,
    productRepository: productRepository,
    saleRepository: saleRepository,
    diagnosticLogger: diagnosticLogger,
  );
  final returnRepository = ReturnRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    customerCreditRepository: customerCreditRepository,
  );
  // Finance additions — same grouping-not-interleaving reasoning as the
  // Category/Supplier/CustomerCredit/DraftCart/Return group above.
  final expenseCategoryRepository = ExpenseCategoryRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  // Mirrors customerCreditRepository above — works exactly like the
  // customer credit book, opposite direction.
  final supplierCreditRepository = SupplierCreditRepositoryImpl(db: database);
  final taxRemittanceRepository = TaxRemittanceRepositoryImpl(db: database);
  final financeStatsRepository = FinanceStatsRepositoryImpl(
    db: database,
    customerCreditRepository: customerCreditRepository,
  );
  final cashDrawerShiftRepository = CashDrawerShiftRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    authRepository: authRepository,
  );
  // LocationRepository also creates locations locally (mobile-side
  // location management), so it needs the same syncQueue dependency
  // supplierRepository/categoryRepository already take for their own
  // create-locally-then-push path.
  final locationRepository = LocationRepositoryImpl(
    db: database,
    locationsApi: locationsApi,
    syncQueue: syncQueue,
  );
  // createBusiness/updateSettings close a real offline-onboarding gap (a
  // fresh install couldn't complete "create your business" without a
  // server). authRepository must exist first — see the comment right
  // above authRepository's own construction for why.
  final businessSettingsRepository = BusinessSettingsRepositoryImpl(
    db: database,
    businessSettingsApi: businessSettingsApi,
    authRepository: authRepository,
    permissionRepository: permissionRepository,
  );

  // Closes the "no location-resolution mechanism exists anywhere in the
  // app yet" gap — see this class's own doc comment
  // (domain/usecases/active_location_resolver.dart) for exactly what it
  // does. Constructed once here, shared by every consumer through
  // resolveActiveLocationProvider — Sell/Stock/Money/owner_setup_screen
  // all resolve through this same instance rather than each getting its
  // own.
  final resolveActiveLocation = ResolveActiveLocation(
    locationRepository: locationRepository,
    authRepository: authRepository,
    businessSettingsRepository: businessSettingsRepository,
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
  // fall back to regardless of what runs here — that's a real, separate
  // onboarding-UX gap (an eventual "waiting for setup" treatment), not
  // something built as part of choosing this trigger.
  //
  // Gated behind syncConfig.isEnabled: these three calls are the one
  // place in bootstrap.dart that reaches the network on an ongoing
  // (well, once-per-launch) basis outside of auth/approval-pin sync, so
  // they're the one place here that needs an explicit check rather than
  // relying on sync_triggers.dart's own internal guards (which don't
  // cover these three at all — they call *Api directly, bypassing
  // SyncTriggers/SyncEngine entirely, per the paragraph above).
  if (syncConfig.isEnabled) {
    unawaited(locationRepository.syncFromServer().catchError((_) {}));
    unawaited(businessSettingsRepository.syncFromServer().catchError((_) {}));
    unawaited(productRepository.syncFromServer().catchError((_) {}));
  }

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
  final categorySyncHandler = CategorySyncHandler(
    categoriesApi: categoriesApi,
    categoryRepository: categoryRepository,
  );
  final supplierSyncHandler = SupplierSyncHandler(
    suppliersApi: suppliersApi,
    supplierRepository: supplierRepository,
  );
  final locationSyncHandler = LocationSyncHandler(
    locationsApi: locationsApi,
    locationRepository: locationRepository,
  );
  final returnSyncHandler = ReturnSyncHandler(
    returnsApi: returnsApi,
    returnRepository: returnRepository,
  );
  final expenseCategorySyncHandler = ExpenseCategorySyncHandler(
    expenseCategoriesApi: expenseCategoriesApi,
    expenseCategoryRepository: expenseCategoryRepository,
  );
  final cashDrawerShiftSyncHandler = CashDrawerShiftSyncHandler(
    cashDrawerShiftsApi: cashDrawerShiftsApi,
    cashDrawerShiftRepository: cashDrawerShiftRepository,
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
  // Phase 0 completion pass.
  final productSyncHandler = ProductSyncHandler(
    db: database,
    productsApi: productsApi,
    productRepository: productRepository,
  );
  final syncEngine = SyncEngine(
    db: database,
    handlersByEntityType: {
      'sale': saleSyncHandler,
      'customer': customerSyncHandler,
      'category': categorySyncHandler,
      'supplier': supplierSyncHandler,
      'location': locationSyncHandler,
      'return': returnSyncHandler,
      'expense_category': expenseCategorySyncHandler,
      'cash_drawer_shift': cashDrawerShiftSyncHandler,
      'expense': expenseSyncHandler,
      'income_record': incomeSyncHandler,
      'stock_movement': stockMovementSyncHandler,
      'product': productSyncHandler,
    },
    // Passed explicitly so this and syncStatusNotifier below are
    // guaranteed to agree — see defaultSyncAttentionThreshold's own doc
    // comment (sync/sync_status_notifier.dart) for why that's a named
    // constant now rather than two independent literal 5s.
    maxAttemptsBeforeAttentionNeeded: defaultSyncAttentionThreshold,
    diagnosticLogger: diagnosticLogger,
  );

  // --- Notifications ---
  // Constructed before syncStatusNotifier below, which depends on it.
  final notificationRepository = NotificationRepositoryImpl(db: database);
  final notificationService = NotificationService(
    notificationRepository: notificationRepository,
  );

  final syncStatusNotifier = SyncStatusNotifier(
    db: database,
    syncConfig: syncConfig,
    notificationService: notificationService,
  );

  final syncTriggers = SyncTriggers(
    syncEngine: syncEngine,
    syncConfig: syncConfig,
    syncStatusNotifier: syncStatusNotifier,
  );
  // Safe to call unconditionally regardless of syncConfig — start()'s
  // own first line returns immediately when sync is disabled, without
  // registering any listener. See sync_triggers.dart's doc comment.
  await syncTriggers.start();

  syncQueue.setOnEnqueued(syncTriggers.notifyEnqueued);

  // --- Device Services ---
  final printerRepository = PrinterRepositoryImpl(db: database);
  final receiptPrinterService = ReceiptPrinterService(
    printerRepository: printerRepository,
  );
  final printerDiscoveryService = PrinterDiscoveryService();
  final barcodeScannerService = BarcodeScannerService();
  final cameraService = CameraService();

  // --- Search / Export ---
  final searchRepository = SearchRepositoryImpl(db: database);
  final globalSearch = GlobalSearch(searchRepository: searchRepository);
  final exportService = ExportService();

  final importProductsFromCsv = ImportProductsFromCsv(
    productRepository: productRepository,
    categoryRepository: categoryRepository,
    supplierRepository: supplierRepository,
  );

  // --- Stages 9-12: Receipts, Backup, Employees, Dashboard/Reports ---
  final employeeRepository = EmployeeRepositoryImpl(db: database);
  final receiptRepository = ReceiptRepositoryImpl(db: database);
  // See AppDatabaseLifecycle's own doc comment for exactly what
  // reopening after a restore does and does not achieve for the
  // repositories constructed above, all of which captured today's
  // `database` value directly rather than through this same
  // lifecycle's indirection.
  final appDatabaseLifecycle = AppDatabaseLifecycle(
    getDatabase: () => database,
    onReopened: (fresh) => database = fresh,
  );
  final backupRepository = BackupRepositoryImpl(lifecycle: appDatabaseLifecycle);
  final dashboardRepository = DashboardRepositoryImpl(db: database);
  final reportsRepository = ReportsRepositoryImpl(db: database);

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      secureStorageProvider.overrideWithValue(secureStorage),
      apiClientProvider.overrideWithValue(apiClient),
      authApiProvider.overrideWithValue(authApi),
      auditRepositoryProvider.overrideWithValue(auditRepository),
      authRepositoryProvider.overrideWithValue(authRepository),
      permissionRepositoryProvider.overrideWithValue(permissionRepository),
      approvalPinRepositoryProvider.overrideWithValue(approvalPinRepository),
      salesApiProvider.overrideWithValue(salesApi),
      customersApiProvider.overrideWithValue(customersApi),
      expensesApiProvider.overrideWithValue(expensesApi),
      syncQueueProvider.overrideWithValue(syncQueue),
      saleRepositoryProvider.overrideWithValue(saleRepository),
      customerRepositoryProvider.overrideWithValue(customerRepository),
      customerCreditRepositoryProvider.overrideWithValue(customerCreditRepository),
      draftCartRepositoryProvider.overrideWithValue(draftCartRepository),
      returnsApiProvider.overrideWithValue(returnsApi),
      returnRepositoryProvider.overrideWithValue(returnRepository),
      cashDrawerShiftsApiProvider.overrideWithValue(cashDrawerShiftsApi),
      cashDrawerShiftRepositoryProvider.overrideWithValue(cashDrawerShiftRepository),
      expenseRepositoryProvider.overrideWithValue(expenseRepository),
      expenseCategoriesApiProvider.overrideWithValue(expenseCategoriesApi),
      expenseCategoryRepositoryProvider.overrideWithValue(expenseCategoryRepository),
      incomeApiProvider.overrideWithValue(incomeApi),
      incomeRecordRepositoryProvider.overrideWithValue(incomeRecordRepository),
      stockMovementsApiProvider.overrideWithValue(stockMovementsApi),
      stockMovementRepositoryProvider.overrideWithValue(stockMovementRepository),
      productsApiProvider.overrideWithValue(productsApi),
      productRepositoryProvider.overrideWithValue(productRepository),
      categoriesApiProvider.overrideWithValue(categoriesApi),
      categoryRepositoryProvider.overrideWithValue(categoryRepository),
      suppliersApiProvider.overrideWithValue(suppliersApi),
      supplierRepositoryProvider.overrideWithValue(supplierRepository),
      supplierCreditRepositoryProvider.overrideWithValue(supplierCreditRepository),
      taxRemittanceRepositoryProvider.overrideWithValue(taxRemittanceRepository),
      financeStatsRepositoryProvider.overrideWithValue(financeStatsRepository),
      locationsApiProvider.overrideWithValue(locationsApi),
      locationRepositoryProvider.overrideWithValue(locationRepository),
      resolveActiveLocationProvider.overrideWithValue(resolveActiveLocation),
      businessSettingsApiProvider.overrideWithValue(businessSettingsApi),
      businessSettingsRepositoryProvider.overrideWithValue(businessSettingsRepository),
      fulusBusinessContextProvider.overrideWithValue(fulusBusinessContext),
      fulusConnectionStateProvider.overrideWithValue(fulusConnectionState),
      syncEngineProvider.overrideWithValue(syncEngine),
      syncTriggersProvider.overrideWithValue(syncTriggers),
      syncConfigProvider.overrideWith((ref) => syncConfig),
      syncStatusNotifierProvider.overrideWithValue(syncStatusNotifier),
      // Onboarding polish
      onboardingStateProvider.overrideWithValue(onboardingState),
      notificationRepositoryProvider.overrideWithValue(notificationRepository),
      notificationServiceProvider.overrideWithValue(notificationService),
      searchRepositoryProvider.overrideWithValue(searchRepository),
      globalSearchProvider.overrideWithValue(globalSearch),
      importProductsFromCsvProvider.overrideWithValue(importProductsFromCsv),
      exportServiceProvider.overrideWithValue(exportService),
      printerRepositoryProvider.overrideWithValue(printerRepository),
      receiptPrinterServiceProvider.overrideWithValue(receiptPrinterService),
      printerDiscoveryServiceProvider.overrideWithValue(printerDiscoveryService),
      barcodeScannerServiceProvider.overrideWithValue(barcodeScannerService),
      cameraServiceProvider.overrideWithValue(cameraService),
      // Stages 9-12
      employeeRepositoryProvider.overrideWithValue(employeeRepository),
      receiptRepositoryProvider.overrideWithValue(receiptRepository),
      backupRepositoryProvider.overrideWithValue(backupRepository),
      dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
      reportsRepositoryProvider.overrideWithValue(reportsRepository),
      // Diagnostic & Crash Logging System
      diagnosticLoggerProvider.overrideWithValue(diagnosticLogger),
    ],
  );

  return container;
}
