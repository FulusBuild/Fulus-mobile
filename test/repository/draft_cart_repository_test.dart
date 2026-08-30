import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/products_api.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/draft_cart_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/product_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/db_seed_helpers.dart';

class MockProductsApi extends Mock implements ProductsApi {}

/// Hand-rolled rather than a Mock — the only member SaleRepositoryImpl
/// actually reads is [currentUser], and this avoids any dependence on
/// exactly how an unstubbed mocktail getter behaves, which nothing in
/// this codebase has had a working toolchain to verify.
class _FakeAuthRepository implements AuthRepository {
  @override
  AuthUser? get currentUser => null;
  @override
  Future<bool> hasAnyOwnerAccount() async => throw UnimplementedError();
  @override
  Future<AuthUser?> restoreSession() async => throw UnimplementedError();
  @override
  Future<AuthUser> createFirstOwner({required String fullName}) async =>
      throw UnimplementedError();
  @override
  Future<void> setOwnLoginPin({required String pin}) async => throw UnimplementedError();
  @override
  Future<List<AuthUser>> listLocalIdentities() async => throw UnimplementedError();
  @override
  Future<AuthUser> switchLocalUser({required String userId, String? pin}) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createAdditionalOwner({required String fullName, required String pin}) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String pin,
    AuthRole role = AuthRole.employee,
  }) async => throw UnimplementedError();
  @override
  Future<void> logout() async => throw UnimplementedError();
  @override
  Future<String?> getActiveLocationId() async => throw UnimplementedError();
  @override
  Future<void> setActiveLocationId(String locationId) async => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DraftCartRepositoryImpl draftCartRepository;
  late SaleRepositoryImpl saleRepository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // draft_carts.location_id carries a foreign key to locations, so
    // every draft cart created in these tests needs a matching
    // locations row seeded first — loc-1 covers all tests except the
    // multi-location one below, which seeds loc-2 itself.
    await seedLocation(db, localId: 'loc-1');
    final syncQueue = SyncQueue(db);
    final productRepository = ProductRepositoryImpl(
      db: db,
      productsApi: MockProductsApi(),
      syncQueue: syncQueue,
    );
    saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: syncQueue,
      authRepository: _FakeAuthRepository(),
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db),
    );
    draftCartRepository = DraftCartRepositoryImpl(
      db: db,
      productRepository: productRepository,
      saleRepository: saleRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('completeSale', () {
    test('a Quick-Sale-only cart still completes locally', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await draftCartRepository.addItem(
        draftCartLocalId: draft.localId,
        description: 'Hand-cut firewood bundle',
        quantity: 2,
        unitPrice: 500,
      );

      final sale = await draftCartRepository.completeSale(draft.localId);

      expect(sale.items, hasLength(1));
      expect(sale.items.first.productLocalId, isNull);
      expect(sale.items.first.description, 'Hand-cut firewood bundle');
      expect(sale.subtotal, 1000);
    });

    test('combines whole-cart and line discounts into one aggregate', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await draftCartRepository.addItem(
        draftCartLocalId: draft.localId,
        description: 'Item A',
        quantity: 1,
        unitPrice: 1000,
        lineDiscount: 50,
      );
      await draftCartRepository.setWholeCartDiscount(
        draftCartLocalId: draft.localId,
        discount: 100,
      );

      final sale = await draftCartRepository.completeSale(draft.localId);

      expect(sale.discount, 150);
      expect(sale.wholeCartDiscount, 100);
    });

    test('aggregates multiple payment legs into paymentMethod=split', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await draftCartRepository.addItem(
        draftCartLocalId: draft.localId,
        description: 'Item A',
        quantity: 1,
        unitPrice: 5000,
      );
      await draftCartRepository.addPayment(
        draftCartLocalId: draft.localId,
        method: 'cash',
        amount: 2000,
      );
      await draftCartRepository.addPayment(
        draftCartLocalId: draft.localId,
        method: 'transfer',
        amount: 3000,
      );

      final sale = await draftCartRepository.completeSale(draft.localId);

      expect(sale.paymentMethod, 'split');
      expect(sale.amountPaid, 5000);
    });

    test(
        'clears the draft cart on success — getOrCreateDraftCart starts '
        'fresh next time', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await draftCartRepository.addItem(
        draftCartLocalId: draft.localId,
        description: 'Item A',
        quantity: 1,
        unitPrice: 1000,
      );

      await draftCartRepository.completeSale(draft.localId);

      final items = await draftCartRepository.watchItems(draft.localId).first;
      expect(items, isEmpty);
    });

    test('rejects completing an empty cart', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await expectLater(
        draftCartRepository.completeSale(draft.localId),
        throwsStateError,
      );
    });

    test('rejects a Quick Sale item with no description', () async {
      final draft = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      await expectLater(
        draftCartRepository.addItem(
          draftCartLocalId: draft.localId,
          quantity: 1,
          unitPrice: 500,
        ),
        throwsArgumentError,
      );
    });

    // Regression test for a confirmed bug (audit finding F-2):
    // completeSale used to call SaleRepository.createSale (which
    // commits its own transaction) and then, as a separate step,
    // clearDraft — so a failure in that second step left a real,
    // committed sale behind while completeSale still threw, and
    // PaymentScreen's catch block told the cashier "nothing was
    // charged." A retry from the same cart then created a second,
    // duplicate sale. completeSale now runs both steps inside one
    // _db.transaction(); this proves that transaction actually rolls
    // the sale back too when something after it fails — the same
    // structure completeSale itself now uses — rather than assuming
    // Drift's nested-transaction behavior works the way the fix
    // depends on.
    test(
        'regression (F-2): a failure after the sale is written rolls the '
        'sale back too, instead of leaving an orphaned, already-charged '
        'sale behind', () async {
      final saleDraft = SaleDraft(
        items: [
          SaleItem(
            localId: 'regression-f2-item',
            description: 'Item A',
            quantity: 1,
            unitPrice: 1000,
            costPriceAtSale: 0,
          ),
        ],
        locationId: 'loc-1',
        amountPaid: 1000,
      );

      await expectLater(
        db.transaction(() async {
          await saleRepository.createSale(saleDraft);
          throw StateError('simulated failure after the sale write');
        }),
        throwsStateError,
      );

      final salesRows = await db.select(db.sales).get();
      expect(
        salesRows,
        isEmpty,
        reason:
            'the sale write must roll back with everything else in the same '
            'transaction, or a retry after this exact failure would create '
            'a second, duplicate sale',
      );
    });
  });

  group('getOrCreateDraftCart', () {
    test('returns the same cart for the same location on a second call',
        () async {
      final first = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      final second = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      expect(second.localId, first.localId);
    });

    test('different locations get different carts', () async {
      await seedLocation(db, localId: 'loc-2', name: 'Second Store');
      final a = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-1',
      );
      final b = await draftCartRepository.getOrCreateDraftCart(
        locationId: 'loc-2',
      );
      expect(a.localId, isNot(b.localId));
    });
  });
}
