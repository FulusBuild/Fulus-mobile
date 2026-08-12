import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../core/export/export_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/security/password_hasher.dart';
import '../core/security/pin_hasher.dart';
import '../data/local/database/app_database_lifecycle.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
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
/// opens first because everything else (secure storage doesn't depend on
/// it, but the eventual repository layer does) should be able to assume
/// it's ready.
///
/// **Merge note (integrating Stages 1-4 + 9-12 + 13-17):** the Stage
/// 13-17 session's own version of this comment claimed
/// "AuthRepositoryImpl currently has no local-authentication path at
/// all (login() calls _authApi.login() directly)" as the reason
/// ApiClient/AuthApi stay unconditional rather than gated behind
/// SyncConfig. That claim was accurate against the bare checkpoint that
/// session had visibility into, not against Stage 2's actual
/// implementation (which that session never received — see
/// HANDOVER-2.md's own audit trail on this exact point). It's moot now
/// either way: AuthRepositoryImpl.login() is fully local since Stage 2
/// (no ApiClient/AuthApi involvement at all — see that file's own doc
/// comment), so there's no login-availability reason left to keep
/// ApiClient/AuthApi unconditional. They stay unconditional anyway,
/// for a reason that doesn't depend on any of that: constructing them is
/// inert (ApiClient's own doc comment — building a Dio instance makes no
/// network call by itself), and ApprovalPinRepositoryImpl's push/pull
/// still uses AuthApi regardless of the general sync toggle (Stage 3's
/// own reasoning: an owner's approval PIN sync is a narrower, separate
/// concern from bulk catalog/settings sync). What Stage 16 actually
/// gates: the three read-repository pull-sync calls below, and (inside
/// sync_triggers.dart itself) every path that would start the sync
/// engine or touch the network on an ongoing basis.
Future<ProviderContainer> bootstrap() async {
  // AppDatabase.open() uses LazyDatabase internally (see database.dart) —
  // the actual file I/O is deferred until the first query, not blocking
  // here, but the object itself is real and ready to be depended on by
  // the time this function returns.
  //
  // `var`, not `final`: AppDatabaseLifecycle (Stage 10/Backup) needs to
  // be able to swap this to a freshly-reopened instance after a restore
  // closes the original connection — see that class's own doc comment
  // for exactly what this does and does not achieve regarding the
  // repositories constructed below, which capture today's value directly
  // and are NOT retroactively updated by a later reassignment here.
  var database = AppDatabase.open();

  final secureStorage = SecureStorage();

  // Stage 16: loaded early, right alongside the other basic infra above,
  // since it gates several of the steps immediately below — see
  // SyncConfig's own doc comment for why this defaults to disabled and
  // what that default is actually claiming.
  final syncConfig = await SyncConfig.load();

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

  final authApi = AuthApi(apiClient);

  // Constructed before AuthRepositoryImpl on purpose: AuthRepositoryImpl
  // depends on AuditRepository (to log login/logout/account-creation
  // events, Stage 3), and AuditRepositoryImpl has no dependency on
  // AuthRepository at all — see AuditRepository.getAuditLogs' own doc
  // comment on why that asymmetry is deliberate, not an oversight; the
  // reverse would make the two impossible to construct.
  final auditRepository = AuditRepositoryImpl(db: database);

  final authRepository = AuthRepositoryImpl(
    db: database,
    passwordHasher: const Argon2PasswordHasher(),
    auditRepository: auditRepository,
  );

  // Was: "attempt a silent refresh using the stored refresh token before
  // showing any login screen at all," per Architecture Section 6 —
  // Architecture Redesign: restoreSession() is now a plain local Sessions
  // + Users table lookup, no network call at all, so awaiting it here
  // costs nothing and there's no "network failure" branch left to reason
  // about — it either finds a valid local session or it doesn't.
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
  final saleRepository = SaleRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    authRepository: authRepository,
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
  // Phase 0 completion pass: Product is no longer read + pull-sync
  // only — createProduct/updateProduct now push through the same
  // SyncQueue/SyncEngine machinery every other write-capable repository
  // here does (Product Design Bible Volume 6, "Adding & Managing
  // Products" is a real mobile capability, confirmed directly against
  // the Bible's own text — see ProductRepository's interface doc for
  // the fuller reasoning).
  final productRepository = ProductRepositoryImpl(
    db: database,
    productsApi: productsApi,
    syncQueue: syncQueue,
  );
  // Stages 5-8 additions (Category/Supplier/CustomerCredit/DraftCart/
  // Return) — inserted here rather than interleaved individually
  // above, since every one of them needs at least productRepository
  // (already constructed by this point) and some need each other too;
  // grouping them keeps the dependency order legible in one place
  // instead of scattered.
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
  // No sync queue at all — every write path this repository has is
  // marked settled by convention today; see CustomerCreditRepository's
  // own doc comment and CustomerLedgerEntryType's per-variant reasoning
  // for exactly why.
  final customerCreditRepository = CustomerCreditRepositoryImpl(db: database);
  // The actual Decision 14 cart-persistence layer — see
  // DraftCartRepository's own doc comment. Depends on both
  // productRepository (price/name lookups when adding a catalog item)
  // and saleRepository (completeSale's bridge to a real, synced Sale) —
  // both already constructed above.
  final draftCartRepository = DraftCartRepositoryImpl(
    db: database,
    productRepository: productRepository,
    saleRepository: saleRepository,
  );
  final returnRepository = ReturnRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    customerCreditRepository: customerCreditRepository,
  );
  // Finance (Stage 8) additions — same grouping-not-interleaving
  // reasoning as the Category/Supplier/CustomerCredit/DraftCart/Return
  // group above.
  final expenseCategoryRepository = ExpenseCategoryRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
  );
  // Mirrors customerCreditRepository above — Decision 26's "works
  // exactly like the customer credit book," opposite direction.
  final supplierCreditRepository = SupplierCreditRepositoryImpl(db: database);
  final taxRemittanceRepository = TaxRemittanceRepositoryImpl(db: database);
  final financeStatsRepository = FinanceStatsRepositoryImpl(db: database);
  final cashDrawerShiftRepository = CashDrawerShiftRepositoryImpl(
    db: database,
    syncQueue: syncQueue,
    authRepository: authRepository,
  );
  // CORRECTED: this used to say "read + pull-sync only, deliberately no
  // create/update method" — LocationRepository now also creates
  // locations locally (mobile-side location management), so it needs
  // the same syncQueue dependency supplierRepository/categoryRepository
  // already take for their own create-locally-then-push path.
  final locationRepository = LocationRepositoryImpl(
    db: database,
    locationsApi: locationsApi,
    syncQueue: syncQueue,
  );
  // STALE COMMENT CORRECTED (Stage 4): this used to say "read +
  // pull-sync only, matching the backend's BusinessProfile having no
  // create/update path from mobile either" — Stage 4 added
  // createBusiness/updateSettings to close a real offline-onboarding
  // gap (a fresh install couldn't complete "create your business"
  // without a server). authRepository must exist first — see the
  // comment right above authRepository's own construction for why.
  final businessSettingsRepository = BusinessSettingsRepositoryImpl(
    db: database,
    businessSettingsApi: businessSettingsApi,
    authRepository: authRepository,
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
  // fall back to regardless of what runs here — that's a real,
  // separate onboarding-UX gap (the Product Design Bible's eventual
  // "waiting for setup" treatment), not something built as part of
  // choosing this trigger.
  //
  // Stage 16: gated behind syncConfig.isEnabled — these three calls are
  // the one place in bootstrap.dart that reaches the network on an
  // ongoing (well, once-per-launch) basis outside of auth/approval-pin
  // sync, so they're the one place here that needs an explicit check
  // rather than relying on sync_triggers.dart's own internal guards
  // (which don't cover these three at all — they call *Api directly,
  // bypassing SyncTriggers/SyncEngine entirely, per the paragraph
  // above).
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
    // Stage 16: passed explicitly so this and syncStatusNotifier below
    // are guaranteed to agree — see defaultSyncAttentionThreshold's own
    // doc comment (sync/sync_status_notifier.dart) for why that's a
    // named constant now rather than two independent literal 5s.
    maxAttemptsBeforeAttentionNeeded: defaultSyncAttentionThreshold,
  );

  // --- Stage 13: Notifications ---
  // Constructed before syncStatusNotifier below, which depends on it.
  final notificationRepository = NotificationRepositoryImpl(db: database);
  final notificationService = NotificationService(
    notificationRepository: notificationRepository,
  );

  // --- Stage 16: Sync Layer Repositioning (status/notification tie-in) ---
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

  // --- Stage 15: Device Services ---
  final printerRepository = PrinterRepositoryImpl(db: database);
  final receiptPrinterService = ReceiptPrinterService(
    printerRepository: printerRepository,
  );
  final printerDiscoveryService = PrinterDiscoveryService();
  final barcodeScannerService = BarcodeScannerService();
  final cameraService = CameraService();

  // --- Stage 14: Search / Export ---
  final searchRepository = SearchRepositoryImpl(db: database);
  final globalSearch = GlobalSearch(searchRepository: searchRepository);
  final exportService = ExportService();

  // Phase 0 completion pass — Product Design Bible Volume 6, "Bulk
  // Import."
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
      syncEngineProvider.overrideWithValue(syncEngine),
      syncTriggersProvider.overrideWithValue(syncTriggers),
      // Stage 16
      syncConfigProvider.overrideWithValue(syncConfig),
      syncStatusNotifierProvider.overrideWithValue(syncStatusNotifier),
      // Stage 13
      notificationRepositoryProvider.overrideWithValue(notificationRepository),
      notificationServiceProvider.overrideWithValue(notificationService),
      // Stage 14
      searchRepositoryProvider.overrideWithValue(searchRepository),
      globalSearchProvider.overrideWithValue(globalSearch),
      importProductsFromCsvProvider.overrideWithValue(importProductsFromCsv),
      exportServiceProvider.overrideWithValue(exportService),
      // Stage 15
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
    ],
  );

  return container;
}
