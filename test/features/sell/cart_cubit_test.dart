import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/business_settings_api.dart';
import 'package:fulus_mobile/data/remote/endpoints/products_api.dart';
import 'package:fulus_mobile/data/repositories/business_settings_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/draft_cart_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/product_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/features/sell/presentation/cubit/cart_cubit.dart';
import 'package:fulus_mobile/features/sell/presentation/cubit/cart_state.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/db_seed_helpers.dart';

class MockProductsApi extends Mock implements ProductsApi {}

class MockBusinessSettingsApi extends Mock implements BusinessSettingsApi {}

/// Hand-rolled, not a mocking-library Mock — matches the pattern already
/// used in the repository tests. The only member read anywhere in this
/// file's code paths is [currentUser].
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.currentUser);

  @override
  final AuthUser? currentUser;
  @override
  Future<bool> hasAnyOwnerAccount() async => throw UnimplementedError();
  @override
  Future<AuthUser?> restoreSession() async => throw UnimplementedError();
  @override
  Future<AuthUser> createFirstOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> login({required String username, required String password}) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createAdditionalOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String username,
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> logout() async => throw UnimplementedError();
  @override
  Future<String?> getActiveLocationId() async => throw UnimplementedError();
  @override
  Future<void> setActiveLocationId(String locationId) async => throw UnimplementedError();
}

/// Waits until [cubit]'s state is a [CartLoaded] satisfying [predicate] —
/// checks the current state first (in case it's already true), otherwise
/// listens for the next one that is. Needed because CartCubit's mutation
/// methods (addProduct, completeSale, ...) resolve once their write to
/// DraftCartRepository completes, not once that write has come back
/// around through the watch streams _emitLoaded() reads from — those are
/// two separate async hops, so checking `cubit.state` immediately after
/// `await`ing a mutation is not reliable on its own.
Future<CartLoaded> waitFor(
  CartCubit cubit,
  bool Function(CartLoaded state) predicate,
) async {
  final current = cubit.state;
  if (current is CartLoaded && predicate(current)) return current;
  final result = await cubit.stream
      .timeout(const Duration(seconds: 5))
      .firstWhere((s) => s is CartLoaded && predicate(s));
  return result as CartLoaded;
}

void main() {
  late AppDatabase db;
  late CartCubit cubit;

  const locationId = 'loc-1';
  const plentyProductId = 'prod-plenty';
  const limitedProductId = 'prod-limited';

  Future<void> seedProduct({
    required String localId,
    required String sku,
    required int stock,
    double sellingPrice = 1000,
    double costPrice = 600,
    bool isActive = true,
  }) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: localId,
            name: localId,
            sku: sku,
            costPrice: costPrice,
            sellingPrice: sellingPrice,
            isActive: Value(isActive),
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
    await db.into(db.productStockLevels).insert(
          ProductStockLevelsCompanion.insert(
            productLocalId: localId,
            locationLocalId: locationId,
            currentStock: Value(stock),
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedLocation(db, localId: locationId);
    await seedUser(db, localId: 'user-cashier-1');
    await seedProduct(localId: plentyProductId, sku: 'SKU-PLENTY', stock: 100);
    await seedProduct(localId: limitedProductId, sku: 'SKU-LIMITED', stock: 2);

    final syncQueue = SyncQueue(db);
    final authRepository = _FakeAuthRepository(
      const AuthUser(
        id: 'user-cashier-1',
        username: 'cashier1',
        email: 'cashier1@test.local',
        fullName: 'Test Cashier',
        role: AuthRole.employee,
        isActive: true,
      ),
    );
    final productRepository = ProductRepositoryImpl(
      db: db,
      productsApi: MockProductsApi(),
      syncQueue: syncQueue,
    );
    final customerRepository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
    // Left unseeded deliberately: no business_settings row means
    // watchSettings() emits null, _profile stays null, and _applyTax()
    // no-ops — exactly right for these tests, none of which are about
    // VAT. currencySymbol falls back to its own '₦' default in that case.
    final businessSettingsRepository = BusinessSettingsRepositoryImpl(
      db: db,
      businessSettingsApi: MockBusinessSettingsApi(),
      authRepository: authRepository,
    );
    final saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: syncQueue,
      authRepository: authRepository,
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db),
    );
    final draftCartRepository = DraftCartRepositoryImpl(
      db: db,
      productRepository: productRepository,
      saleRepository: saleRepository,
    );

    cubit = CartCubit(
      draftCartRepository: draftCartRepository,
      productRepository: productRepository,
      customerRepository: customerRepository,
      businessSettingsRepository: businessSettingsRepository,
      locationId: locationId,
    );
    await waitFor(cubit, (s) => s.catalogLoaded);
  });

  tearDown(() async {
    await cubit.close();
    await db.close();
  });

  group('addProduct', () {
    test('adds a new product as a line item', () async {
      await cubit.addProduct(plentyProductId);
      final state = await waitFor(cubit, (s) => s.items.isNotEmpty);

      expect(state.items, hasLength(1));
      expect(state.items.single.productLocalId, plentyProductId);
      expect(state.items.single.quantity, 1);
    });

    test('adding the same product again increments the existing line '
        'instead of duplicating it', () async {
      await cubit.addProduct(plentyProductId);
      await waitFor(cubit, (s) => s.items.isNotEmpty);
      await cubit.addProduct(plentyProductId);
      final state = await waitFor(cubit, (s) => s.itemCount == 2);

      expect(state.items, hasLength(1));
      expect(state.items.single.quantity, 2);
    });

    test('throws once adding another unit would exceed available stock',
        () async {
      await cubit.addProduct(limitedProductId); // 1 of 2
      await waitFor(cubit, (s) => s.itemCount == 1);
      await cubit.addProduct(limitedProductId); // 2 of 2
      await waitFor(cubit, (s) => s.itemCount == 2);

      await expectLater(
        cubit.addProduct(limitedProductId), // would be 3 of 2
        throwsStateError,
      );
      // The rejected attempt must not have partially applied.
      final state = cubit.state as CartLoaded;
      expect(state.itemCount, 2);
    });

    test('throws for a product that is not in the catalog', () async {
      await expectLater(
        cubit.addProduct('does-not-exist'),
        throwsStateError,
      );
    });
  });

  group('incrementItem / decrementItem / setItemQuantity', () {
    test('incrementItem throws once the line already holds all available '
        'stock', () async {
      await cubit.addProduct(limitedProductId);
      await cubit.addProduct(limitedProductId);
      final state = await waitFor(cubit, (s) => s.itemCount == 2);
      final line = state.items.single;

      await expectLater(cubit.incrementItem(line), throwsStateError);
    });

    test('decrementItem removes the line entirely once quantity would '
        'drop to zero', () async {
      await cubit.addProduct(plentyProductId);
      final state = await waitFor(cubit, (s) => s.items.isNotEmpty);
      final line = state.items.single;

      await cubit.decrementItem(line);
      final after = await waitFor(cubit, (s) => s.items.isEmpty);
      expect(after.items, isEmpty);
    });

    test('setItemQuantity rejects a quantity above available stock',
        () async {
      await cubit.addProduct(limitedProductId);
      final state = await waitFor(cubit, (s) => s.items.isNotEmpty);
      final line = state.items.single;

      await expectLater(
        cubit.setItemQuantity(line, 3),
        throwsStateError,
      );
    });

    test('setItemQuantity rejects zero', () async {
      await cubit.addProduct(plentyProductId);
      final state = await waitFor(cubit, (s) => s.items.isNotEmpty);
      final line = state.items.single;

      await expectLater(
        cubit.setItemQuantity(line, 0),
        throwsStateError,
      );
    });
  });

  group('discounts', () {
    test('setWholeCartDiscount rejects a discount larger than the '
        'subtotal', () async {
      await cubit.addProduct(plentyProductId); // subtotal = 1000
      await waitFor(cubit, (s) => s.items.isNotEmpty);

      await expectLater(
        cubit.setWholeCartDiscount(1001),
        throwsStateError,
      );
    });

    test('setWholeCartDiscount rejects a negative discount', () async {
      await cubit.addProduct(plentyProductId);
      await waitFor(cubit, (s) => s.items.isNotEmpty);

      await expectLater(
        cubit.setWholeCartDiscount(-1),
        throwsStateError,
      );
    });

    test('updateItemDiscount rejects a discount larger than the line '
        'total', () async {
      await cubit.addProduct(plentyProductId); // lineTotal = 1000
      final state = await waitFor(cubit, (s) => s.items.isNotEmpty);
      final line = state.items.single;

      await expectLater(
        cubit.updateItemDiscount(line, 1001),
        throwsStateError,
      );
    });
  });

  group('addQuickSaleItem', () {
    test('rejects an empty description', () async {
      await expectLater(
        cubit.addQuickSaleItem(description: '   ', unitPrice: 500),
        throwsStateError,
      );
    });

    test('rejects a non-positive price', () async {
      await expectLater(
        cubit.addQuickSaleItem(description: 'Firewood', unitPrice: 0),
        throwsStateError,
      );
    });
  });

  group('completeSale', () {
    test('submitting is true during completion and false again once it '
        'succeeds', () async {
      await cubit.addProduct(plentyProductId);
      await waitFor(cubit, (s) => s.items.isNotEmpty);
      await cubit.addPayment('cash', 1000);
      await waitFor(cubit, (s) => s.payments.isNotEmpty);

      final future = cubit.completeSale();
      // completeSale sets _submitting = true and emits synchronously
      // before its first await, so this should already be visible.
      expect((cubit.state as CartLoaded).submitting, isTrue);

      await future;
      expect((cubit.state as CartLoaded).submitting, isFalse);
    });

    // Regression coverage tying together with audit finding F-2: this
    // doesn't re-verify DraftCartRepositoryImpl's own transaction (see
    // draft_cart_repository_test.dart for that) — it verifies the
    // Cubit layer on top of it behaves correctly when completeSale
    // fails: submitting must reset to false (not get stuck true,
    // leaving the Pay button permanently disabled) so a genuine retry
    // is actually possible.
    test('submitting resets to false after a failed completeSale, so the '
        'cart is ready to retry', () async {
      // An empty cart is guaranteed to fail — DraftCartRepositoryImpl
      // itself rejects it before ever opening a transaction.
      await expectLater(cubit.completeSale(), throwsStateError);

      final state = cubit.state as CartLoaded;
      expect(state.submitting, isFalse);
      expect(state.items, isEmpty);
    });

    test('a successful sale totals what was in the cart and leaves the '
        'cart empty afterward', () async {
      await cubit.addProduct(plentyProductId);
      await cubit.addProduct(limitedProductId);
      await waitFor(cubit, (s) => s.items.length == 2);
      await cubit.addPayment('cash', 2000);
      await waitFor(cubit, (s) => s.payments.isNotEmpty);

      final sale = await cubit.completeSale();

      expect(sale.total, 2000);
      expect(sale.items, hasLength(2));

      final after = await waitFor(cubit, (s) => s.items.isEmpty);
      expect(after.items, isEmpty);
      expect(after.payments, isEmpty);
      expect(after.submitting, isFalse);
    });
  });
}
