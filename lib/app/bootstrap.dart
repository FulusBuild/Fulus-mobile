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
  final expenseCategorySyncHandler = ExpenseCategorySyncHandler(expenseCategoriesApi: expenseCategoriesApi, expenseCategoryRepository: expenseCategoryRepository);
  final cashDrawerShiftSyncHandler = CashDrawerShiftSyncHandler(cashDrawerShiftsApi: cashDrawerShiftsApi, cashDrawerShiftRepository: cashDrawerShiftRepository);
  final expenseSyncHandler = ExpenseSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, expenseRepository: expenseRepository);
  final incomeSyncHandler = IncomeSyncHandler(incomeApi: incomeApi, incomeRecordRepository: incomeRecordRepository);
  final stockMovementSyncHandler = StockMovementSyncHandler(db: database, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState, stockMovementRepository: stockMovementRepository, productRepository: productRepository);
  final productSyncHandler = ProductSyncHandler(db: database, productRepository: productRepository, fulusSyncApi: fulusSyncApi, fulusConnectionState: fulusConnectionState);
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
  final syncTriggers = SyncTriggers(
    syncEngine: syncEngine,
    syncConfig: syncConfig,
    syncStatusNotifier: syncStatusNotifier,
    isReady: () async => fulusConnectionState.isSyncReady,
    pullFromServer: () async {
      if (!syncConfig.isEnabled) return;
      await locationRepository.syncFromServer();
      await businessSettingsRepository.syncFromServer();
      await productRepository.syncFromServer();
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
  final employeeRepository = EmployeeRepositoryImpl(db: database);
  final receiptRepository = ReceiptRepositoryImpl(db: database);
  final appDatabaseLifecycle = AppDatabaseLifecycle(getDatabase: () => database, onReopened: (fresh) => database = fresh);
  final backupRepository = BackupRepositoryImpl(lifecycle: appDatabaseLifecycle);
  final dashboardRepository = DashboardRepositoryImpl(db: database);
  final reportsRepository = ReportsRepositoryImpl(db: database);

  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database), secureStorageProvider.overrideWithValue(secureStorage), apiClientProvider.overrideWithValue(apiClient), authApiProvider.overrideWithValue(authApi), auditRepositoryProvider.overrideWithValue(auditRepository), authRepositoryProvider.overrideWithValue(authRepository), permissionRepositoryProvider.overrideWithValue(permissionRepository), approvalPinRepositoryProvider.overrideWithValue(approvalPinRepository), salesApiProvider.overrideWithValue(salesApi), customersApiProvider.overrideWithValue(customersApi), expensesApiProvider.overrideWithValue(expensesApi), expenseCategoriesApiProvider.overrideWithValue(expenseCategoriesApi), incomeApiProvider.overrideWithValue(incomeApi), stockMovementsApiProvider.overrideWithValue(stockMovementsApi), productsApiProvider.overrideWithValue(productsApi), categoriesApiProvider.overrideWithValue(categoriesApi), suppliersApiProvider.overrideWithValue(suppliersApi), returnsApiProvider.overrideWithValue(returnsApi), cashDrawerShiftsApiProvider.overrideWithValue(cashDrawerShiftsApi), locationsApiProvider.overrideWithValue(locationsApi), businessSettingsApiProvider.overrideWithValue(businessSettingsApi), syncQueueProvider.overrideWithValue(syncQueue), customerCreditRepositoryProvider.overrideWithValue(customerCreditRepository), saleRepositoryProvider.overrideWithValue(saleRepository), customerRepositoryProvider.overrideWithValue(customerRepository), expenseRepositoryProvider.overrideWithValue(expenseRepository), incomeRecordRepositoryProvider.overrideWithValue(incomeRecordRepository), stockMovementRepositoryProvider.overrideWithValue(stockMovementRepository), productRepositoryProvider.overrideWithValue(productRepository), categoryRepositoryProvider.overrideWithValue(categoryRepository), supplierRepositoryProvider.overrideWithValue(supplierRepository), returnRepositoryProvider.overrideWithValue(returnRepository), expenseCategoryRepositoryProvider.overrideWithValue(expenseCategoryRepository), supplierCreditRepositoryProvider.overrideWithValue(supplierCreditRepository), taxRemittanceRepositoryProvider.overrideWithValue(taxRemittanceRepository), financeStatsRepositoryProvider.overrideWithValue(financeStatsRepository), cashDrawerShiftRepositoryProvider.overrideWithValue(cashDrawerShiftRepository), locationRepositoryProvider.overrideWithValue(locationRepository), businessSettingsRepositoryProvider.overrideWithValue(businessSettingsRepository), resolveActiveLocationProvider.overrideWithValue(resolveActiveLocation), draftCartRepositoryProvider.overrideWithValue(draftCartRepository), printerRepositoryProvider.overrideWithValue(printerRepository), receiptPrinterServiceProvider.overrideWithValue(receiptPrinterService), printerDiscoveryServiceProvider.overrideWithValue(printerDiscoveryService), barcodeScannerServiceProvider.overrideWithValue(barcodeScannerService), cameraServiceProvider.overrideWithValue(cameraService), globalSearchProvider.overrideWithValue(globalSearch), exportServiceProvider.overrideWithValue(exportService), importProductsFromCsvProvider.overrideWithValue(importProductsFromCsv), employeeRepositoryProvider.overrideWithValue(employeeRepository), receiptRepositoryProvider.overrideWithValue(receiptRepository), backupRepositoryProvider.overrideWithValue(backupRepository), dashboardRepositoryProvider.overrideWithValue(dashboardRepository), reportsRepositoryProvider.overrideWithValue(reportsRepository), onboardingStateProvider.overrideWithValue(onboardingState), diagnosticLoggerProvider.overrideWithValue(diagnosticLogger), notificationRepositoryProvider.overrideWithValue(notificationRepository), notificationServiceProvider.overrideWithValue(notificationService), syncConfigProvider.overrideWith((ref) => syncConfig), syncStatusNotifierProvider.overrideWithValue(syncStatusNotifier), syncEngineProvider.overrideWithValue(syncEngine), syncTriggersProvider.overrideWithValue(syncTriggers), fulusBusinessContextProvider.overrideWithValue(fulusBusinessContext), fulusDeviceRegistrationProvider.overrideWithValue(fulusDeviceRegistration), fulusSyncApiProvider.overrideWithValue(fulusSyncApi), fulusStaffAccessApiProvider.overrideWithValue(fulusStaffAccessApi), fulusConnectionStateProvider.overrideWith((ref) => fulusConnectionState),
    ],
  );
}