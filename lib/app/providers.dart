import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved out of the main flutter_riverpod export in 3.0 —
// still fully supported, just needs this import now. See:
// https://riverpod.dev/docs/3.0_migration
import 'package:flutter_riverpod/legacy.dart';

import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_event.dart';
import '../core/export/export_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/onboarding/onboarding_state.dart';
import '../core/security/app_lock_config.dart';
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
import '../device_services/camera/camera_service.dart';
import '../device_services/printing/printer_discovery_service.dart';
import '../device_services/printing/receipt_printer_service.dart';
import '../device_services/scanning/barcode_scanner_service.dart';
import '../domain/entities/auth_user.dart';
import '../domain/repositories/approval_pin_repository.dart';
import '../domain/repositories/audit_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/backup_repository.dart';
import '../domain/repositories/business_settings_repository.dart';
import '../domain/repositories/cash_drawer_shift_repository.dart';
import '../domain/repositories/customer_credit_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/dashboard_repository.dart';
import '../domain/repositories/draft_cart_repository.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/repositories/employee_repository.dart';
import '../domain/repositories/expense_category_repository.dart';
import '../domain/repositories/expense_repository.dart';
import '../domain/repositories/finance_stats_repository.dart';
import '../domain/repositories/income_record_repository.dart';
import '../domain/repositories/location_repository.dart';
import '../domain/repositories/notification_repository.dart';
import '../domain/repositories/printer_repository.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/receipt_repository.dart';
import '../domain/repositories/reports_repository.dart';
import '../domain/repositories/return_repository.dart';
import '../domain/repositories/sale_repository.dart';
import '../domain/repositories/search_repository.dart';
import '../domain/repositories/stock_movement_repository.dart';
import '../domain/repositories/supplier_credit_repository.dart';
import '../domain/repositories/supplier_repository.dart';
import '../domain/repositories/tax_remittance_repository.dart';
import '../domain/usecases/active_location_resolver.dart';
import '../domain/usecases/global_search.dart';
import '../domain/usecases/import_products_from_csv.dart';
import '../sync/sync_config.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_status_notifier.dart';
import '../sync/sync_triggers.dart';

/// The app-wide DI graph's entry points. Each of these is declared with
/// a body that throws UnimplementedError if it's ever actually invoked —
/// deliberately, not accidentally. These providers are never meant to run
/// their own declared body; bootstrap.dart's ProviderContainer(overrides:
/// [...]) always supplies a real value before the widget tree (built with
/// UncontrolledProviderScope, per main.dart) ever reads from them. The
/// throw exists specifically so that IF a future change accidentally
/// removes an override in bootstrap.dart, the failure is a loud, explicit
/// UnimplementedError at the exact provider that's missing its override —
/// not a silent null or a real-looking placeholder object that would let
/// a wiring mistake pass unnoticed until much further downstream.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in bootstrap.dart — this is a DI '
    'entry point, not a default implementation.',
  );
});

final secureStorageProvider = Provider<SecureStorage>((ref) {
  throw UnimplementedError(
    'secureStorageProvider must be overridden in bootstrap.dart.',
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError(
    'apiClientProvider must be overridden in bootstrap.dart.',
  );
});

final authApiProvider = Provider<AuthApi>((ref) {
  throw UnimplementedError(
    'authApiProvider must be overridden in bootstrap.dart.',
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw UnimplementedError(
    'authRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

/// Foundation phase 3 (Owner setup / sign-in). `AuthRepository.
/// currentUser` is a plain getter, not reactive — its own doc comment
/// says why: "no login/session-aware screen built yet to consume one;
/// revisit once Volume 3's actual onboarding/login UI gets built." This
/// is that revisit. Riverpod's `ref.watch` only rebuilds when a
/// *provider* changes, not when a plain field inside the object a
/// provider returns mutates internally — so router.dart watching
/// `ref.watch(authRepositoryProvider).currentUser` directly would never
/// rebuild after a real sign-in, since AuthRepositoryImpl's
/// `_currentUser` field changes with no provider-level signal attached
/// to it.
///
/// This provider is a thin, purely additive state holder — it does not
/// call AuthRepository itself, and AuthRepositoryImpl is untouched by
/// this phase. It's seeded once from whatever bootstrap.dart's
/// `restoreSession()` already resolved before the widget tree first
/// builds (a real restored session, or null), and from then on it's
/// each mutating call site's own job to write the new value here right
/// after its underlying AuthRepository call actually succeeds —
/// `identity_picker_screen.dart` and `owner_setup_screen.dart` do this
/// now; logout, whenever a Settings screen adds one, will need to as
/// well.
final sessionProvider = StateProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).currentUser;
});

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  throw UnimplementedError(
    'auditRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final approvalPinRepositoryProvider = Provider<ApprovalPinRepository>((ref) {
  throw UnimplementedError(
    'approvalPinRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final salesApiProvider = Provider<SalesApi>((ref) {
  throw UnimplementedError(
    'salesApiProvider must be overridden in bootstrap.dart.',
  );
});

final customersApiProvider = Provider<CustomersApi>((ref) {
  throw UnimplementedError(
    'customersApiProvider must be overridden in bootstrap.dart.',
  );
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  throw UnimplementedError(
    'customerRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final customerCreditRepositoryProvider = Provider<CustomerCreditRepository>((ref) {
  throw UnimplementedError(
    'customerCreditRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final expensesApiProvider = Provider<ExpensesApi>((ref) {
  throw UnimplementedError(
    'expensesApiProvider must be overridden in bootstrap.dart.',
  );
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  throw UnimplementedError(
    'expenseRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final expenseCategoriesApiProvider = Provider<ExpenseCategoriesApi>((ref) {
  throw UnimplementedError(
    'expenseCategoriesApiProvider must be overridden in bootstrap.dart.',
  );
});

final expenseCategoryRepositoryProvider =
    Provider<ExpenseCategoryRepository>((ref) {
  throw UnimplementedError(
    'expenseCategoryRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final incomeApiProvider = Provider<IncomeApi>((ref) {
  throw UnimplementedError(
    'incomeApiProvider must be overridden in bootstrap.dart.',
  );
});

final incomeRecordRepositoryProvider = Provider<IncomeRecordRepository>((ref) {
  throw UnimplementedError(
    'incomeRecordRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final stockMovementsApiProvider = Provider<StockMovementsApi>((ref) {
  throw UnimplementedError(
    'stockMovementsApiProvider must be overridden in bootstrap.dart.',
  );
});

final stockMovementRepositoryProvider = Provider<StockMovementRepository>((ref) {
  throw UnimplementedError(
    'stockMovementRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final productsApiProvider = Provider<ProductsApi>((ref) {
  throw UnimplementedError(
    'productsApiProvider must be overridden in bootstrap.dart.',
  );
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  throw UnimplementedError(
    'productRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final categoriesApiProvider = Provider<CategoriesApi>((ref) {
  throw UnimplementedError(
    'categoriesApiProvider must be overridden in bootstrap.dart.',
  );
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  throw UnimplementedError(
    'categoryRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final suppliersApiProvider = Provider<SuppliersApi>((ref) {
  throw UnimplementedError(
    'suppliersApiProvider must be overridden in bootstrap.dart.',
  );
});

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  throw UnimplementedError(
    'supplierRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final supplierCreditRepositoryProvider = Provider<SupplierCreditRepository>((ref) {
  throw UnimplementedError(
    'supplierCreditRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final taxRemittanceRepositoryProvider = Provider<TaxRemittanceRepository>((ref) {
  throw UnimplementedError(
    'taxRemittanceRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final financeStatsRepositoryProvider = Provider<FinanceStatsRepository>((ref) {
  throw UnimplementedError(
    'financeStatsRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final locationsApiProvider = Provider<LocationsApi>((ref) {
  throw UnimplementedError(
    'locationsApiProvider must be overridden in bootstrap.dart.',
  );
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  throw UnimplementedError(
    'locationRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final resolveActiveLocationProvider = Provider<ResolveActiveLocation>((ref) {
  throw UnimplementedError(
    'resolveActiveLocationProvider must be overridden in bootstrap.dart.',
  );
});

/// The single source of truth for "which location is active right
/// now" — every Sell/Stock/Money call site should watch this instead
/// of inventing its own resolution or fallback. A real, self-contained
/// implementation (not a throw-stub): unlike the repository providers
/// above, this doesn't wrap a concrete Drift/Dio dependency that only
/// bootstrap.dart can construct — it's a thin FutureProvider wrapper
/// around [resolveActiveLocationProvider] (itself already overridden in
/// bootstrap.dart), the same "derived, not overridden" shape
/// [sessionProvider] above uses for the equivalent reason.
///
/// autoDispose deliberately omitted: this is app-wide session state
/// (which physical location this device is looking at), not screen-
/// scoped derived state — re-running the resolution (and its DB round
/// trip) every time a user switches tabs away from Sell/Stock/Money and
/// back would be wasted work for a value that essentially never changes
/// mid-session.
final activeLocationIdProvider = FutureProvider<String>((ref) {
  return ref.watch(resolveActiveLocationProvider).call();
});

final businessSettingsApiProvider = Provider<BusinessSettingsApi>((ref) {
  throw UnimplementedError(
    'businessSettingsApiProvider must be overridden in bootstrap.dart.',
  );
});

final businessSettingsRepositoryProvider = Provider<BusinessSettingsRepository>((ref) {
  throw UnimplementedError(
    'businessSettingsRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final syncQueueProvider = Provider<SyncQueue>((ref) {
  throw UnimplementedError(
    'syncQueueProvider must be overridden in bootstrap.dart.',
  );
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  throw UnimplementedError(
    'saleRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final draftCartRepositoryProvider = Provider<DraftCartRepository>((ref) {
  throw UnimplementedError(
    'draftCartRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final returnsApiProvider = Provider<ReturnsApi>((ref) {
  throw UnimplementedError(
    'returnsApiProvider must be overridden in bootstrap.dart.',
  );
});

final returnRepositoryProvider = Provider<ReturnRepository>((ref) {
  throw UnimplementedError(
    'returnRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final cashDrawerShiftsApiProvider = Provider<CashDrawerShiftsApi>((ref) {
  throw UnimplementedError(
    'cashDrawerShiftsApiProvider must be overridden in bootstrap.dart.',
  );
});

final cashDrawerShiftRepositoryProvider =
    Provider<CashDrawerShiftRepository>((ref) {
  throw UnimplementedError(
    'cashDrawerShiftRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  throw UnimplementedError(
    'syncEngineProvider must be overridden in bootstrap.dart.',
  );
});

/// Exposed specifically for the future "Sync Now" button (Volume 11)
/// and a sync-status indicator to call `.syncNow()` — not for the
/// automatic triggers themselves, which start once in bootstrap.dart
/// regardless of whether any UI ever reads this provider.
final syncTriggersProvider = Provider<SyncTriggers>((ref) {
  throw UnimplementedError(
    'syncTriggersProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Stage 16 — Sync Layer Repositioning
// ---------------------------------------------------------------------

/// A future Settings "Offline, Sync & Backup" screen (Volume 11) reads
/// this to show the toggle's current state and calls
/// SyncConfig.setEnabled to flip it — see that class's own doc comment
/// on why flipping it doesn't itself restart SyncTriggers.
final syncConfigProvider = Provider<SyncConfig>((ref) {
  throw UnimplementedError(
    'syncConfigProvider must be overridden in bootstrap.dart.',
  );
});

/// The reactive sync-indicator data source (Volume 2, Volume 12) and the
/// stuck-sync notification check — see sync_status_notifier.dart.
final syncStatusNotifierProvider = Provider<SyncStatusNotifier>((ref) {
  throw UnimplementedError(
    'syncStatusNotifierProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Stage 13 — Notifications
// ---------------------------------------------------------------------

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  throw UnimplementedError(
    'notificationRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Stage 14 — Search / Export
// ---------------------------------------------------------------------

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  throw UnimplementedError(
    'searchRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final globalSearchProvider = Provider<GlobalSearch>((ref) {
  throw UnimplementedError(
    'globalSearchProvider must be overridden in bootstrap.dart.',
  );
});

/// Phase 0 completion pass.
final importProductsFromCsvProvider = Provider<ImportProductsFromCsv>((ref) {
  throw UnimplementedError(
    'importProductsFromCsvProvider must be overridden in bootstrap.dart.',
  );
});

final exportServiceProvider = Provider<ExportService>((ref) {
  throw UnimplementedError(
    'exportServiceProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Stage 15 — Device Services
// ---------------------------------------------------------------------

final printerRepositoryProvider = Provider<PrinterRepository>((ref) {
  throw UnimplementedError(
    'printerRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final receiptPrinterServiceProvider = Provider<ReceiptPrinterService>((ref) {
  throw UnimplementedError(
    'receiptPrinterServiceProvider must be overridden in bootstrap.dart.',
  );
});

final printerDiscoveryServiceProvider = Provider<PrinterDiscoveryService>((ref) {
  throw UnimplementedError(
    'printerDiscoveryServiceProvider must be overridden in bootstrap.dart.',
  );
});

final barcodeScannerServiceProvider = Provider<BarcodeScannerService>((ref) {
  throw UnimplementedError(
    'barcodeScannerServiceProvider must be overridden in bootstrap.dart.',
  );
});

final cameraServiceProvider = Provider<CameraService>((ref) {
  throw UnimplementedError(
    'cameraServiceProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Stages 9-12 — Receipts, Backup, Employees, Dashboard/Reports
// ---------------------------------------------------------------------

final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) {
  throw UnimplementedError(
    'employeeRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  throw UnimplementedError(
    'receiptRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  throw UnimplementedError(
    'backupRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  throw UnimplementedError(
    'dashboardRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

/// Gap fix: Home's hero state used to be a plain `Future` cached in
/// [HomeScreen]'s own State (see that screen's header comment), fetched
/// once in `initState` and never again — so opening or closing the
/// drawer elsewhere (Money's opening-float sheet, Daily Closing)
/// updated the real data `DashboardRepository` reads, but Home kept
/// showing whatever it fetched before either action happened, since
/// nothing ever told it to re-fetch. `HomeScreen` deliberately keeps its
/// own Future-based fetch (its own doc comment: testability in
/// isolation with plain constructor params, not a session-reading
/// provider) — this is the smallest fix that respects that: a counter
/// Home listens to and reloads on change, bumped by whichever screen
/// actually changed the drawer/day state. Not scoped to one action
/// specifically — anything that changes what Home's hero reflects bumps
/// it, the same way `ref.invalidate` is used elsewhere in this app.
final dashboardRefreshSignalProvider = StateProvider<int>((ref) => 0);

/// Gap fix: App Lock (Volume 11) — self-sufficient like the signal
/// above, not routed through bootstrap.dart's override pattern, since
/// AppLockConfig.load() needs nothing bootstrap.dart already
/// constructs (just SharedPreferences, fetched fresh via
/// SharedPreferences.getInstance()'s own internal caching).
final appLockConfigProvider = FutureProvider<AppLockConfig>((ref) => AppLockConfig.load());

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  throw UnimplementedError(
    'reportsRepositoryProvider must be overridden in bootstrap.dart.',
  );
});

// ---------------------------------------------------------------------
// Nice-to-have gap closure — Volume 3: Onboarding polish
// ---------------------------------------------------------------------

final onboardingStateProvider = Provider<OnboardingState>((ref) {
  throw UnimplementedError(
    'onboardingStateProvider must be overridden in bootstrap.dart.',
  );
});

/// Reactive mirror of [OnboardingState.hasSeenFirstRunPrompt] — same
/// shape, and same reason, as [sessionProvider] mirroring
/// `AuthRepository.currentUser` above: `_ShellGate` (router.dart) needs
/// to rebuild the instant this flips, and `ref.watch` only reacts to a
/// *provider* changing, not to a plain field mutating inside whatever
/// object a provider returns. Seeded once from the real, persisted
/// value; every call site that flips the underlying flag (currently
/// just [FirstRunSetupScreen]) writes here too, right after its
/// `OnboardingState` call succeeds.
final firstRunPromptSeenProvider = StateProvider<bool>((ref) {
  return ref.watch(onboardingStateProvider).hasSeenFirstRunPrompt;
});

/// Reactive mirror of [OnboardingState.walkthroughStep] — same shape,
/// same reason, as [firstRunPromptSeenProvider] immediately above:
/// `_ShellGate` needs to rebuild the instant this changes, and
/// `ref.watch` only reacts to a *provider* changing. Whichever
/// walkthrough screen advances the step writes here too, right after
/// its `OnboardingState` call succeeds.
final walkthroughStepProvider = StateProvider<OnboardingStep?>((ref) {
  return ref.watch(onboardingStateProvider).walkthroughStep;
});

/// Deliberately NOT backed by [OnboardingState] / SharedPreferences,
/// unlike every provider above it: whether the walkthrough's brief
/// "now let's sell it" interstitial has been dismissed *this session*
/// isn't onboarding progress — [OnboardingStep.firstSale] itself is
/// already the durable fact that this span is in progress. If the app
/// restarts mid-first-sale, showing this one-time interstitial again is
/// a fine, low-cost re-show, not a second source of truth to keep in
/// sync with the first.
final firstSaleIntroSeenProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------
// Diagnostic & Crash Logging System
// ---------------------------------------------------------------------

/// Unlike every other provider in this file, [diagnosticLogger] is
/// constructed in main.dart, before `bootstrap()` even runs — not
/// inside bootstrap.dart alongside everything above — specifically so
/// error capture is live for the whole bootstrap process itself (see
/// main.dart's own header comment). This provider exists so the rest
/// of the app (in particular the Diagnostics screens) can still reach
/// that same instance the ordinary way, through `ref.watch`, rather
/// than needing a different access pattern just because of when it was
/// constructed.
final diagnosticLoggerProvider = Provider<DiagnosticLogger>((ref) {
  throw UnimplementedError(
    'diagnosticLoggerProvider must be overridden in bootstrap.dart.',
  );
});

/// The Diagnostics screen's own data source — every currently-stored
/// event, newest first, up to a generous cap. Both the summary header
/// ("N Errors / N Warnings") and the filtered/searched list the screen
/// renders are derived from this SAME fetch (client-side, in the
/// screen itself) rather than two separate providers, so the two can
/// never disagree with each other over what "right now" means.
///
/// The cap (500) is not a hidden page size the person is meant to
/// scroll past — it deliberately matches [DiagnosticLogger.applyRetentionPolicy]'s
/// own default `keepAtLeast`, so in ordinary operation (retention
/// already keeps the table near this size) the header count and the
/// true on-device total agree exactly; only an extraordinary single
/// session generating hundreds of events between app restarts would
/// see the header undercount slightly until the next cold start prunes
/// the table back down.
final diagnosticEventsProvider = StreamProvider.autoDispose<List<DiagnosticEvent>>((ref) {
  return ref.watch(diagnosticLoggerProvider).watchEvents(limit: 500);
});

final diagnosticEventByIdProvider =
    FutureProvider.autoDispose.family<DiagnosticEvent?, String>((ref, id) {
  return ref.watch(diagnosticLoggerProvider).getById(id);
});
