import 'dart:async';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/env_config.dart';
import '../core/config/supabase_config.dart';
import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/storage/drift_diagnostic_store.dart';
import '../core/export/export_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/security/pin_hasher.dart';
import '../core/onboarding/onboarding_state.dart';
import '../data/local/database/app_database_lifecycle.dart';
import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/fulus_business_context.dart';
import '../data/remote/fulus_canonical_reconciler_typed.dart';
import '../data/remote/fulus_cash_drawer_canonical_reconciler.dart';
import '../data/remote/fulus_category_canonical_reconciler.dart';
import '../data/remote/fulus_connection_state.dart';
import '../data/remote/fulus_customer_canonical_reconciler.dart';
import '../data/remote/fulus_customer_ledger_canonical_reconciler.dart';
import '../data/remote/fulus_device_registration.dart';
import '../data/remote/fulus_expense_canonical_reconciler.dart';
import '../data/remote/fulus_expense_category_canonical_reconciler.dart';
import '../data/remote/fulus_income_canonical_reconciler.dart';
import '../data/remote/fulus_location_canonical_reconciler.dart';
import '../data/remote/fulus_product_canonical_reconciler.dart';
import '../data/remote/fulus_return_canonical_reconciler.dart';
import '../data/remote/fulus_sale_canonical_reconciler.dart';
import '../data/remote/fulus_staff_access_api.dart';
import '../data/remote/fulus_stock_movement_canonical_reconciler.dart';
import '../data/remote/fulus_sync_api.dart';
import '../data/remote/fulus_supplier_canonical_reconciler.dart';
import '../data/remote/fulus_sync_coordinator.dart';
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
import '../data/repositories/return_canonical_repository_impl.dart';
import '../data/repositories/return_repository_impl.dart';
import '../data/repositories/sale_canonical_repository_impl.dart';
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
import '../sync/handlers/customer_ledger_sync_handler.dart';
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

Future<ProviderContainer> bootstrap({required DiagnosticLogger diagnosticLogger}) async {
  var database = AppDatabase.open();
  diagnosticLogger.attachStore(DriftDiagnosticStore(database));
  unawaited(diagnosticLogger.applyRetentionPolicy());
  final secureStorage = SecureStorage();
  final syncConfig = await SyncConfig.load();
  final syncPreferences = await SharedPreferences.getInstance();
  final onboardingState = await OnboardingState.load();
  const baseUrl = EnvConfig.apiBaseUrl;
  late final ApiClient apiClient;
  apiClient = ApiClient(baseUrl: baseUrl, secureStorage: secureStorage, onSessionExpired: () async {});

  final fulusFunctionBaseUrl = '${SupabaseConfig.url}/functions/v1/fulus-api';
  final fulusBusinessContext = FulusBusinessContext(client: apiClient, functionBaseUrl: fulusFunctionBaseUrl);
  final fulusDeviceRegistration = FulusDeviceRegistration(client: apiClient, functionBaseUrl: fulusFunctionBaseUrl);
  final fulusSyncApi = FulusSyncApi(client: apiClient, functionBaseUrl: fulusFunctionBaseUrl);
  final fulusStaffAccessApi = FulusStaffAccessApi(client: apiClient, functionBaseUrl: '${SupabaseConfig.url}/functions/v1/fulus-staff-api');
  final fulusConnectionState = FulusConnectionState(
    businessContext: fulusBusinessContext,
    deviceRegistration: fulusDeviceRegistration,
    staffAccessApi: fulusStaffAccessApi,
  );
  final authApi = AuthApi(apiClient);
  final deviceClientId = await secureStorage.ensureDeviceClientId(Ulid().toString());

  final auditRepository = AuditRepositoryImpl(db: database);
  final permissionRepository = PermissionRepositoryImpl(db: database);
  final authRepository = AuthRepositoryImpl(db: database, pinHasher: const Argon2PinHasher(), auditRepository: auditRepository, permissionRepository: permissionRepository);
  await authRepository.restoreSession();
  final approvalPinRepository = ApprovalPinRepositoryImpl(authApi: authApi, secureStorage: secureStorage, pinHasher: const Argon2PinHasher(), auditRepository: auditRepository);

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

  final customerCreditRepository = CustomerCreditRepositoryImpl(db: database, syncQueue: syncQueue);
  final saleRepository = SaleRepositoryImpl(db: database, syncQueue: syncQueue, authRepository: authRepository, customerCreditRepository: customerCreditRepository, diagnosticLogger: diagnosticLogger);
  final saleCanonicalRepository = SaleCanonicalRepositoryImpl(db: database);
  final customerRepository = CustomerRepositoryImpl(db: database, syncQueue: syncQueue);
  final expenseRepository = ExpenseRepositoryImpl(db: database, syncQueue: syncQueue, auditRepository: auditRepository);
  final incomeRecordRepository = IncomeRecordRepositoryImpl(db: database, syncQueue: syncQueue);
  final stockMovementRepository = StockMovementRepositoryImpl(db: database, syncQueue: syncQueue);
  final productRepository = ProductRepositoryImpl(db: database, productsApi: productsApi, syncQueue: syncQueue);
  final categoryRepository = CategoryRepositoryImpl(db: database, syncQueue: syncQueue);
  final supplierRepository = SupplierRepositoryImpl(db: database, syncQueue: syncQueue);
  final draftCartRepository = DraftCartRepositoryImpl(db: database, productRepository: productRepository, saleRepository: saleRepository, diagnosticLogger: diagnosticLogger);
  final returnRepository = ReturnRepositoryImpl(db: database, syncQueue: syncQueue, customerCreditRepository: customerCreditRepository);
  final returnCanonicalRepository = ReturnCanonicalRepositoryImpl(db: database);
  final expenseCategoryRepository = ExpenseCategoryRepositoryImpl(db: database, syncQueue: syncQueue);
  final supplierCreditRepository = SupplierCreditRepositoryImpl(db: database);
  final taxRemittanceRepository = TaxRemittanceRepositoryImpl(db: database);
  final financeStatsRepository = FinanceStatsRepositoryImpl(db: database, customerCreditRepository: customerCreditRepository);
  final cashDrawerShiftRepository = CashDrawerShiftRepositoryImpl(db: database, syncQueue: syncQueue, authRepository: authRepository);
  final locationRepository = LocationRepositoryImpl(db: database, locationsApi: locationsApi, syncQueue: syncQueue);
  final businessSettingsRepository = BusinessSettingsRepositoryImpl(db: database, businessSettingsApi: businessSettingsApi, authRepository: authRepository, permissionRepository: permissionRepository);
  final resolveActiveLocation = ResolveActiveLocation(locationRepository: locationRepository, authRepository: authRepository, businessSettingsRepository: businessSettingsRepository);

  final saleSyncHandler = SaleSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, salesApi: salesApi, saleRepository: saleRepository);
  final customerSyncHandler = CustomerSyncHandler(fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, customerRepository: customerRepository);
  final customerLedgerSyncHandler = CustomerLedgerSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, secureStorage: secureStorage);
  final categorySyncHandler = CategorySyncHandler(categoryRepository: categoryRepository, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState);
  final supplierSyncHandler = SupplierSyncHandler(supplierRepository: supplierRepository, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState);
  final locationSyncHandler = LocationSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, locationRepository: locationRepository);
  final returnSyncHandler = ReturnSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, returnRepository: returnRepository);
  final expenseCategorySyncHandler = ExpenseCategorySyncHandler(fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, expenseCategoryRepository: expenseCategoryRepository);
  final cashDrawerShiftSyncHandler = CashDrawerShiftSyncHandler(fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, cashDrawerShiftRepository: cashDrawerShiftRepository, locationRepository: locationRepository);
  final expenseSyncHandler = ExpenseSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, expenseRepository: expenseRepository);
  final incomeSyncHandler = IncomeSyncHandler(fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, incomeRecordRepository: incomeRecordRepository, locationRepository: locationRepository);
  final stockMovementSyncHandler = StockMovementSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, stockMovementRepository: stockMovementRepository, productRepository: productRepository);
  final productSyncHandler = ProductSyncHandler(db: database, productRepository: productRepository, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState);

  final canonicalReconciler = FulusCanonicalTypedReconciler(
    api: fulusSyncApi,
    handlers: {
      'sale': FulusSaleCanonicalReconciler(repository: saleCanonicalRepository).apply,
      'customer': FulusCustomerCanonicalReconciler(repository: customerRepository).apply,
      'customer_ledger': FulusCustomerLedgerCanonicalReconciler(repository: customerCreditRepository).apply,
      'category': FulusCategoryCanonicalReconciler(repository: categoryRepository).apply,
      'supplier': FulusSupplierCanonicalReconciler(repository: supplierRepository).apply,
      'location': FulusLocationCanonicalReconciler(locationRepository).apply,
      'return': FulusReturnCanonicalReconciler(repository: returnCanonicalRepository).apply,
      'expense_category': FulusExpenseCategoryCanonicalReconciler(repository: expenseCategoryRepository).apply,
      'cash_drawer_shift': FulusCashDrawerCanonicalReconciler(repository: cashDrawerShiftRepository).apply,
      'expense': FulusExpenseCanonicalReconciler(repository: expenseRepository).apply,
      'income_record': FulusIncomeCanonicalReconciler(repository: incomeRecordRepository).apply,
      'stock_movement': FulusStockMovementCanonicalReconciler(repository: stockMovementRepository).apply,
      'product': FulusProductCanonicalReconciler(repository: productRepository).apply,
    },
  );
  final syncCoordinator = FulusSyncCoordinator(
    api: fulusSyncApi,
    preferences: syncPreferences,
    applyChange: (change) async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId == null) {
        throw StateError('Fulus Cloud business context is not ready for canonical reconciliation.');
      }
      final registeredDevice = fulusConnectionState.registeredDevice;
      if (registeredDevice == null || !fulusConnectionState.isDeviceAuthorized) {
        throw StateError('Fulus Cloud device registration is not ready.');
      }
      await canonicalReconciler.reconcile(
        change,
        businessId: businessId,
        deviceClientId: registeredDevice.deviceClientId,
      );
    },
  );

  final syncEngine = SyncEngine(
    db: database,
    handlersByEntityType: {
      'sale': saleSyncHandler,
      'customer': customerSyncHandler,
      'customer_ledger': customerLedgerSyncHandler,
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
    maxAttemptsBeforeAttentionNeeded: defaultSyncAttentionThreshold,
    diagnosticLogger: diagnosticLogger,
  );

  final notificationRepository = NotificationRepositoryImpl(db: database);
  final notificationService = NotificationService(notificationRepository: notificationRepository);
  final syncStatusNotifier = SyncStatusNotifier(db: database, syncConfig: syncConfig, notificationService: notificationService);
  late final SyncTriggers syncTriggers;

  Future<void> initializeCloudSync() async {
    final session = await authApi.restoreServerSession(
      supabaseUrl: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    if (session == null) return;
    await fulusConnectionState.refresh();
    final active = fulusConnectionState.membershipContext?.memberships.where((m) => m.status == 'active').toList(growable: false) ?? const [];
    if (active.length != 1) return;
    fulusConnectionState.selectBusiness(active.first.businessId);
    final package = await PackageInfo.fromPlatform();
    await fulusConnectionState.registerDevice(
      deviceClientId: deviceClientId,
      deviceName: 'Fulus Mobile',
      platform: Platform.operatingSystem,
      appVersion: package.version,
    );
    await syncTriggers.reconcileAfterRestore();
    fulusConnectionState.markSyncReady();
  }

  syncTriggers = SyncTriggers(
    syncEngine: syncEngine,
    syncConfig: syncConfig,
    syncStatusNotifier: syncStatusNotifier,
    isReady: () async => fulusConnectionState.isSyncReady,
    onNotReady: initializeCloudSync,
    pullFromServer: () async {
      if (!syncConfig.isEnabled) return;
      final businessId = fulusConnectionState.selectedBusinessId;
      final registeredDevice = fulusConnectionState.registeredDevice;
      if (businessId == null || registeredDevice == null || !fulusConnectionState.isDeviceAuthorized) {
        throw StateError('Fulus Cloud is not ready for canonical pull.');
      }
      await syncCoordinator.pullAndApply(businessId: businessId);
    },
  );
  await syncTriggers.start();
  syncQueue.setOnEnqueued(syncTriggers.notifyEnqueued);

  final printerRepository = PrinterRepositoryImpl(db: database);
  final receiptPrinterService = ReceiptPrinterService(printerRepository: printerRepository);
  final printerDiscoveryService = PrinterDiscoveryService();
  final barcodeScannerService = BarcodeScannerService();
  final cameraService = CameraService();
  final searchRepository = SearchRepositoryImpl(db: database);
  final globalSearch = GlobalSearch(searchRepository: searchRepository);
  final exportService = ExportService();
  final importProductsFromCsv = ImportProductsFromCsv(productRepository: productRepository, categoryRepository: categoryRepository, supplierRepository: supplierRepository);
  // Keep the CSV import use case in the root provider container.
  // This is intentionally wired here because the provider has no default implementation.
  final employeeRepository = EmployeeRepositoryImpl(db: database);
  final receiptRepository = ReceiptRepositoryImpl(db: database);
  final appDatabaseLifecycle = AppDatabaseLifecycle(getDatabase: () => database, onReopened: (fresh) => database = fresh);
  final backupRepository = BackupRepositoryImpl(lifecycle: appDatabaseLifecycle);
  final dashboardRepository = DashboardRepositoryImpl(db: database);
  final reportsRepository = ReportsRepositoryImpl(db: database);

  return ProviderContainer(
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
      expenseCategoriesApiProvider.overrideWithValue(expenseCategoriesApi),
      incomeApiProvider.overrideWithValue(incomeApi),
      stockMovementsApiProvider.overrideWithValue(stockMovementsApi),
      productsApiProvider.overrideWithValue(productsApi),
      categoriesApiProvider.overrideWithValue(categoriesApi),
      suppliersApiProvider.overrideWithValue(suppliersApi),
      returnsApiProvider.overrideWithValue(returnsApi),
      cashDrawerShiftsApiProvider.overrideWithValue(cashDrawerShiftsApi),
      locationsApiProvider.overrideWithValue(locationsApi),
      businessSettingsApiProvider.overrideWithValue(businessSettingsApi),
      syncQueueProvider.overrideWithValue(syncQueue),
      customerCreditRepositoryProvider.overrideWithValue(customerCreditRepository),
      saleRepositoryProvider.overrideWithValue(saleRepository),
      customerRepositoryProvider.overrideWithValue(customerRepository),
      expenseRepositoryProvider.overrideWithValue(expenseRepository),
      incomeRecordRepositoryProvider.overrideWithValue(incomeRecordRepository),
      stockMovementRepositoryProvider.overrideWithValue(stockMovementRepository),
      productRepositoryProvider.overrideWithValue(productRepository),
      categoryRepositoryProvider.overrideWithValue(categoryRepository),
      supplierRepositoryProvider.overrideWithValue(supplierRepository),
      draftCartRepositoryProvider.overrideWithValue(draftCartRepository),
      returnRepositoryProvider.overrideWithValue(returnRepository),
      expenseCategoryRepositoryProvider.overrideWithValue(expenseCategoryRepository),
      supplierCreditRepositoryProvider.overrideWithValue(supplierCreditRepository),
      taxRemittanceRepositoryProvider.overrideWithValue(taxRemittanceRepository),
      financeStatsRepositoryProvider.overrideWithValue(financeStatsRepository),
      cashDrawerShiftRepositoryProvider.overrideWithValue(cashDrawerShiftRepository),
      locationRepositoryProvider.overrideWithValue(locationRepository),
      businessSettingsRepositoryProvider.overrideWithValue(businessSettingsRepository),
      resolveActiveLocationProvider.overrideWithValue(resolveActiveLocation),
      printerRepositoryProvider.overrideWithValue(printerRepository),
      receiptPrinterServiceProvider.overrideWithValue(receiptPrinterService),
      printerDiscoveryServiceProvider.overrideWithValue(printerDiscoveryService),
      barcodeScannerServiceProvider.overrideWithValue(barcodeScannerService),
      cameraServiceProvider.overrideWithValue(cameraService),
      searchRepositoryProvider.overrideWithValue(searchRepository),
      globalSearchProvider.overrideWithValue(globalSearch),
      exportServiceProvider.overrideWithValue(exportService),
      importProductsFromCsvProvider.overrideWithValue(importProductsFromCsv),
      employeeRepositoryProvider.overrideWithValue(employeeRepository),
      receiptRepositoryProvider.overrideWithValue(receiptRepository),
      backupRepositoryProvider.overrideWithValue(backupRepository),
      dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
      reportsRepositoryProvider.overrideWithValue(reportsRepository),
      fulusBusinessContextProvider.overrideWithValue(fulusBusinessContext),
      fulusDeviceRegistrationProvider.overrideWithValue(fulusDeviceRegistration),
      fulusSyncApiProvider.overrideWithValue(fulusSyncApi),
      fulusConnectionStateProvider.overrideWith((ref) => fulusConnectionState),
      fulusStaffAccessApiProvider.overrideWithValue(fulusStaffAccessApi),
      onboardingStateProvider.overrideWithValue(onboardingState),
      syncConfigProvider.overrideWith((ref) => syncConfig),
      diagnosticLoggerProvider.overrideWithValue(diagnosticLogger),
      notificationRepositoryProvider.overrideWithValue(notificationRepository),
      notificationServiceProvider.overrideWithValue(notificationService),
      syncStatusNotifierProvider.overrideWithValue(syncStatusNotifier),
      syncTriggersProvider.overrideWithValue(syncTriggers),
    ],
  );
}
