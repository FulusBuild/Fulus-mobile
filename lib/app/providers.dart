import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/database/database.dart';
import '../data/local/secure_storage/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/endpoints/sales_api.dart';
import '../data/repositories/sale_repository_impl.dart';
import '../domain/repositories/sale_repository.dart';
import '../sync/sync_queue.dart';

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

final salesApiProvider = Provider<SalesApi>((ref) {
  throw UnimplementedError(
    'salesApiProvider must be overridden in bootstrap.dart.',
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
