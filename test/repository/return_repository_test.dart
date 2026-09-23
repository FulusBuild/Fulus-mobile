import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/return_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/return_request.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:ulid/ulid.dart';

import '../helpers/db_seed_helpers.dart';

/// Hand-rolled, not a mocking-library Mock — matches the pattern already
/// used in sale_repository_test.dart / draft_cart_repository_test.dart.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.currentUser);

  @override
  final AuthUser? currentUser;
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

/// Real, no-mocks tests against an in-memory Drift database — same
/// approach as sale_repository_test.dart / draft_cart_repository_test.dart.
/// The "prior purchase" every group here returns against is created
/// through the real SaleRepositoryImpl rather than hand-inserted rows,
/// so its items/total/amountPaid are as internally consistent as a real
/// sale — exactly what ReturnRepositoryImpl's eligibility math reads.
void main() {
  late AppDatabase db;
  late SaleRepositoryImpl saleRepository;
  late CustomerRepositoryImpl customerRepository;
  late ReturnRepositoryImpl returnRepository;

  const locationId = 'loc-1';
  const productAId = 'prod-a';
  const productBId = 'prod-b';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedLocation(db, localId: locationId);
    await seedUser(db, localId: 'user-cashier-1');

    final now = DateTime(2026, 1, 1);
    for (final id in [productAId, productBId]) {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              localId: id,
              name: id,
              sku: 'SKU-$id',
              costPrice: 400,
              sellingPrice: 1000,
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
      await db.into(db.productStockLevels).insert(
            ProductStockLevelsCompanion.insert(
              productLocalId: id,
              locationLocalId: locationId,
              currentStock: const Value(50),
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
    }

    final syncQueue = SyncQueue(db);
    final authRepository = _FakeAuthRepository(
      const AuthUser(
        id: 'user-cashier-1',
        username: 'cashier1',
        email: 'cashier1@test.local',
        fullName: 'Test Cashier',
        role: AuthRole.employee,
        isActive: true,
        hasLoginPin: true,
      ),
    );
    final customerCreditRepository = CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
    saleRepository = SaleRepositoryImpl(
      db: db,
      syncQueue: syncQueue,
      authRepository: authRepository,
      customerCreditRepository: customerCreditRepository,
    );
    returnRepository = ReturnRepositoryImpl(
      db: db,
      syncQueue: syncQueue,
      customerCreditRepository: customerCreditRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// A sale of 5x productA + 3x productB at ₦1000 each, fully paid in
  /// cash unless [customerId]/[amountPaid] say otherwise.
  Future<Sale> purchase({String? customerId, double? amountPaid}) {
    final items = [
      SaleItem(
        localId: Ulid().toString(),
        productLocalId: productAId,
        quantity: 5,
        unitPrice: 1000,
        costPriceAtSale: 400,
      ),
      SaleItem(
        localId: Ulid().toString(),
        productLocalId: productBId,
        quantity: 3,
        unitPrice: 1000,
        costPriceAtSale: 400,
      ),
    ];
    final total = 8000.0;
    return saleRepository.createSale(
      SaleDraft(
        items: items,
        locationId: locationId,
        customerId: customerId,
        amountPaid: amountPaid ?? total,
      ),
    );
  }

  group('getReturnEligibility', () {
    test('reports the full purchased quantity as returnable before any '
        'return exists', () async {
      final sale = await purchase();

      final lines = await returnRepository.getReturnEligibility(sale.localId);

      final a = lines.firstWhere((l) => l.productLocalId == productAId);
      expect(a.purchasedQuantity, 5);
      expect(a.alreadyReturned, 0);
      expect(a.remainingReturnable, 5);
    });

    test('reduces remaining eligibility by a completed return\'s quantity',
        () async {
      final sale = await purchase();
      await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: [const ReturnItemRequest(productLocalId: productAId, quantity: 2)],
        returnReason: 'Wrong size',
        refundMethod: 'cash',
        autoApprove: true,
      );

      final lines = await returnRepository.getReturnEligibility(sale.localId);
      final a = lines.firstWhere((l) => l.productLocalId == productAId);
      expect(a.alreadyReturned, 2);
      expect(a.remainingReturnable, 3);
    });

    test('a rejected return frees its claimed quantity back up', () async {
      final sale = await purchase();
      final firstReturn = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: [const ReturnItemRequest(productLocalId: productAId, quantity: 2)],
        returnReason: 'Changed mind',
        refundMethod: 'cash',
        autoApprove: false,
      );
      await returnRepository.approveOrRejectReturn(
        returnLocalId: firstReturn.localId,
        approve: false,
      );

      final lines = await returnRepository.getReturnEligibility(sale.localId);
      final a = lines.firstWhere((l) => l.productLocalId == productAId);
      expect(a.alreadyReturned, 0,
          reason: 'a rejected return must not still count as claimed');
      expect(a.remainingReturnable, 5);
    });
  });

  group('createReturn', () {
    test('computes the refund amount from the sale\'s own unit price',
        () async {
      final sale = await purchase();

      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: [const ReturnItemRequest(productLocalId: productAId, quantity: 2)],
        returnReason: 'Wrong size',
        refundMethod: 'cash',
        autoApprove: true,
      );

      expect(ret.refundAmount, 2000);
    });

    test('autoApprove: false creates a pending return; true creates an '
        'approved one', () async {
      final sale = await purchase();

      final pending = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: [const ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: false,
      );
      final queuedBeforeCompletion = await (db.select(db.syncQueueItems)
            ..where((q) => q.entityLocalId.equals(pending.localId)))
          .get();
      expect(queuedBeforeCompletion, isEmpty);

      final approved = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: [const ReturnItemRequest(productLocalId: productBId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );
      expect(approved.status, ReturnStatus.approved);

      await returnRepository.completeReturn(approved.localId);
      final queuedAfterCompletion = await (db.select(db.syncQueueItems)
            ..where((q) => q.entityLocalId.equals(approved.localId)))
          .get();
      expect(queuedAfterCompletion, hasLength(1));
      expect(queuedAfterCompletion.single.operation, 'create');
    });

    test('rejects a product that was not part of the original sale',
        () async {
      final sale = await purchase();

      await expectLater(
        returnRepository.createReturn(
          originalSaleLocalId: sale.localId,
          items: const [ReturnItemRequest(productLocalId: 'not-purchased', quantity: 1)],
          returnReason: 'x',
          refundMethod: 'cash',
          autoApprove: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects returning more than was purchased', () async {
      final sale = await purchase(); // 5x productA

      await expectLater(
        returnRepository.createReturn(
          originalSaleLocalId: sale.localId,
          items: const [ReturnItemRequest(productLocalId: productAId, quantity: 6)],
          returnReason: 'x',
          refundMethod: 'cash',
          autoApprove: true,
        ),
        throwsArgumentError,
      );
    });

    // The specific business rule your brief called out by name: "Can
    // already-refunded items be refunded again?" — this proves two
    // separate, valid-on-their-own return requests can't jointly
    // exceed what was purchased, which getReturnEligibility's own
    // tests above only check one request at a time.
    test('rejects a second return that would push cumulative claimed '
        'quantity past what was purchased', () async {
      final sale = await purchase(); // 5x productA
      await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 3)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );

      // 3 already claimed, only 2 remain — this asks for 3 more.
      await expectLater(
        returnRepository.createReturn(
          originalSaleLocalId: sale.localId,
          items: const [ReturnItemRequest(productLocalId: productAId, quantity: 3)],
          returnReason: 'x',
          refundMethod: 'cash',
          autoApprove: true,
        ),
        throwsArgumentError,
      );
    });

    test('two separate partial returns that together exactly use up the '
        'purchased quantity both succeed', () async {
      final sale = await purchase(); // 5x productA
      await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 3)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );
      final second = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 2)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );

      expect(second.refundAmount, 2000);
      final lines = await returnRepository.getReturnEligibility(sale.localId);
      expect(
        lines.firstWhere((l) => l.productLocalId == productAId).remainingReturnable,
        0,
      );
    });

    test('rejects an empty item list', () async {
      final sale = await purchase();
      await expectLater(
        returnRepository.createReturn(
          originalSaleLocalId: sale.localId,
          items: const [],
          returnReason: 'x',
          refundMethod: 'cash',
          autoApprove: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a blank return reason', () async {
      final sale = await purchase();
      await expectLater(
        returnRepository.createReturn(
          originalSaleLocalId: sale.localId,
          items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
          returnReason: '   ',
          refundMethod: 'cash',
          autoApprove: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('approveOrRejectReturn', () {
    test('rejects trying to approve a return that is already approved',
        () async {
      final sale = await purchase();
      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );

      await expectLater(
        returnRepository.approveOrRejectReturn(
          returnLocalId: ret.localId,
          approve: true,
        ),
        throwsStateError,
      );
    });
  });

  group('completeReturn', () {
    test('requires the return to be approved first', () async {
      final sale = await purchase();
      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: false, // stays pending
      );

      await expectLater(
        returnRepository.completeReturn(ret.localId),
        throwsStateError,
      );
    });

    test('restores stock for every returned line', () async {
      final sale = await purchase();
      final before = await (db.select(db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productAId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingle();

      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 2)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );
      await returnRepository.completeReturn(ret.localId);

      final after = await (db.select(db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productAId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingle();
      expect(after.currentStock, before.currentStock + 2);
    });

    test('marks the return completed with inventoryRestored true',
        () async {
      final sale = await purchase();
      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );

      final completed = await returnRepository.completeReturn(ret.localId);

      expect(completed.status, ReturnStatus.completed);
      expect(completed.inventoryRestored, isTrue);
      expect(completed.completedAt, isNotNull);
    });

    test('reduces an outstanding credit balance by the refund amount, '
        'capped at what is actually still owed', () async {
      final customer = await customerRepository.createCustomer(
        const CustomerDraft(name: 'Test Customer'),
      );
      // 8000 total, 3000 paid up front — 5000 still owed on credit.
      final sale = await purchase(customerId: customer.localId, amountPaid: 3000);

      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 5)],
        returnReason: 'x',
        refundMethod: 'account credit',
        autoApprove: true,
      ); // refundAmount = 5000, exactly what's owed
      await returnRepository.completeReturn(ret.localId);

      final updatedCustomer = await customerRepository.getCustomerById(customer.localId);
      expect(updatedCustomer!.outstandingBalance, 0);
    });

    test('does not touch the credit balance when the sale was already '
        'fully paid', () async {
      final customer = await customerRepository.createCustomer(
        const CustomerDraft(name: 'Test Customer'),
      );
      final sale = await purchase(customerId: customer.localId); // fully paid

      final ret = await returnRepository.createReturn(
        originalSaleLocalId: sale.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'x',
        refundMethod: 'cash',
        autoApprove: true,
      );
      await returnRepository.completeReturn(ret.localId);

      final updatedCustomer = await customerRepository.getCustomerById(customer.localId);
      expect(updatedCustomer!.outstandingBalance, 0);
    });
  });

  group('voidSale', () {
    test('claims every unit still eligible, auto-approved and completed '
        'in one call', () async {
      final sale = await purchase(); // 5x productA, 3x productB

      final voided = await returnRepository.voidSale(
        saleLocalId: sale.localId,
        reason: 'Rung up in error',
      );

      expect(voided.status, ReturnStatus.completed);
      expect(voided.isVoid, isTrue);
      expect(voided.inventoryRestored, isTrue);
      expect(voided.items.fold<int>(0, (sum, i) => sum + i.quantity), 8); // 5 + 3

      final lines = await returnRepository.getReturnEligibility(sale.localId);
      for (final line in lines) {
        expect(line.remainingReturnable, 0);
      }
    });

    test('restores stock the same way a completed return does', () async {
      final sale = await purchase();
      final before = await (db.select(db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productAId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingle();

      await returnRepository.voidSale(saleLocalId: sale.localId, reason: 'Mistake');

      final after = await (db.select(db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productAId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingle();
      expect(after.currentStock, before.currentStock + 5); // all 5 units back
    });

    test('uses the original sale\'s own payment method, not a caller-'
        'supplied one', () async {
      // Explicit, non-'cash' payment method — purchase()'s default sale
      // never sets one (falls through to null), which would make this
      // assertion pass for the wrong reason via voidSale's own '??
      // cash' fallback rather than genuinely reading the sale's value.
      final sale = await saleRepository.createSale(
        SaleDraft(
          items: [
            SaleItem(
              localId: 'transfer-item-1',
              productLocalId: productAId,
              quantity: 1,
              unitPrice: 1000,
              costPriceAtSale: 400,
            ),
          ],
          locationId: locationId,
          amountPaid: 1000,
          paymentMethod: 'transfer',
        ),
      );

      final voided = await returnRepository.voidSale(
        saleLocalId: sale.localId,
        reason: 'Mistake',
      );

      expect(voided.refundMethod, 'transfer');
    });

    test('reduces an outstanding credit balance the same way a completed '
        'return does', () async {
      final customer = await customerRepository.createCustomer(
        const CustomerDraft(name: 'Test Customer'),
      );
      final sale = await purchase(customerId: customer.localId, amountPaid: 3000);

      await returnRepository.voidSale(saleLocalId: sale.localId, reason: 'Mistake');

      final updated = await customerRepository.getCustomerById(customer.localId);
      expect(updated!.outstandingBalance, 0);
    });

    test('rejects voiding a sale that has already been fully voided',
        () async {
      final sale = await purchase();
      await returnRepository.voidSale(saleLocalId: sale.localId, reason: 'Mistake');

      await expectLater(
        returnRepository.voidSale(saleLocalId: sale.localId, reason: 'Again?'),
        throwsStateError,
      );
    });

    test('rejects an empty reason', () async {
      final sale = await purchase();

      await expectLater(
        returnRepository.voidSale(saleLocalId: sale.localId, reason: '   '),
        throwsArgumentError,
      );
    });

    test('watchReturns(isVoid: true) only returns voids, not genuine '
        'customer returns', () async {
      final saleA = await purchase();
      final saleB = await purchase();
      await returnRepository.voidSale(saleLocalId: saleA.localId, reason: 'Mistake');
      await returnRepository.createReturn(
        originalSaleLocalId: saleB.localId,
        items: const [ReturnItemRequest(productLocalId: productAId, quantity: 1)],
        returnReason: 'Customer changed mind',
        refundMethod: 'cash',
        autoApprove: true,
      );

      final voids = await returnRepository.watchReturns(isVoid: true).first;
      final returns = await returnRepository.watchReturns(isVoid: false).first;

      expect(voids, hasLength(1));
      expect(voids.single.originalSaleLocalId, saleA.localId);
      expect(returns, hasLength(1));
      expect(returns.single.originalSaleLocalId, saleB.localId);
    });
  });
}
