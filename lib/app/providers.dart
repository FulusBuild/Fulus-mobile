import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../domain/repositories/approval_pin_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/business_settings_repository.dart';
import '../domain/repositories/customer_repository.dart';
import '../domain/repositories/expense_repository.dart';
import '../domain/repositories/income_record_repository.dart';
import '../domain/repositories/location_repository.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/sale_repository.dart';
import '../domain/repositories/stock_movement_repository.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_queue.dart';
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
