import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/sale_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';
import 'package:fulus_mobile/domain/entities/sale_draft.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_seed_helpers.dart';

/// Hand-rolled, not a mocking-library Mock — matches this file's own
/// "no mocks" approach above; the only member SaleRepositoryImpl
/// actually reads is [currentUser].
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository([this.currentUser]);

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

/// Real, no-mocks tests against an in-memory Drift database
/// (AppDatabase.forTesting — see database.dart's own comment on why
/// this constructor exists). No API/network mocking is needed because
/// Architecture Section 4's central rule is exactly what's being
/// verified here: SaleRepositoryImpl.createSale never awaits the
/// network at all — everything it does is a local Drift write plus a
/// local queue insert, both fully exercisable without a server.
void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late SaleRepositoryImpl repository;
  late CustomerRepositoryImpl customerRepository;
  late CustomerCreditRepositoryImpl customerCreditRepository;

  const locationId = 'loc-1';
  const productId = 'prod-1';
  const initialStock = 20;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    customerRepository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
    customerCreditRepository = CustomerCreditRepositoryImpl(db: db);
    repository = SaleRepositoryImpl(
      db: db,
      syncQueue: syncQueue,
      authRepository: _FakeAuthRepository(
        const AuthUser(
          id: 'user-cashier-1',
          username: 'cashier1',
          email: 'cashier1@test.local',
          fullName: 'Test Cashier',
          role: AuthRole.employee,
          isActive: true,
          hasLoginPin: true,
        ),
      ),
      customerCreditRepository: customerCreditRepository,
    );

    final now = DateTime.now();

    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            localId: locationId,
            name: 'Test Location',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );

    // Sales.cashierUserId is a real FK against users(local_id) — the
    // _FakeAuthRepository above attributes every sale to 'user-cashier-1',
    // so that row has to exist first.
    await seedUser(db, localId: 'user-cashier-1');

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: productId,
            name: 'Test Product',
            sku: 'SKU-1',
            costPrice: 100,
            sellingPrice: 150,
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );

    await db.into(db.productStockLevels).insert(
          ProductStockLevelsCompanion.insert(
            productLocalId: productId,
            locationLocalId: locationId,
            currentStock: const Value(initialStock),
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  SaleDraft draftWithOneItem({int quantity = 3}) {
    final item = SaleItem(
      localId: 'item-1',
      productLocalId: productId,
      quantity: quantity,
      unitPrice: 150,
      costPriceAtSale: 100,
    );
    return SaleDraft(
      items: [item],
      locationId: locationId,
      amountPaid: 150 * quantity.toDouble(),
    );
  }

  group('createSale', () {
    test('writes the sale and its item locally', () async {
      final result = await repository.createSale(draftWithOneItem());

      expect(result.total, 450);
      expect(result.items, hasLength(1));

      final salesRows = await db.select(db.sales).get();
      expect(salesRows, hasLength(1));
      expect(salesRows.single.clientReference, result.localId);
      expect(salesRows.single.syncStatus, SyncStatus.pending);

      final itemRows = await db.select(db.saleItems).get();
      expect(itemRows, hasLength(1));
      expect(itemRows.single.saleLocalId, result.localId);
      expect(itemRows.single.productLocalId, productId);
    });

    test('attributes the sale to whoever is signed in', () async {
      final result = await repository.createSale(draftWithOneItem());

      expect(result.cashierUserId, 'user-cashier-1');

      final salesRows = await db.select(db.sales).get();
      expect(salesRows.single.cashierUserId, 'user-cashier-1');
    });

    test('decrements local stock for the sold product at that location',
        () async {
      await repository.createSale(draftWithOneItem(quantity: 3));

      final stockRow = await (db.select(db.productStockLevels)
            ..where(
              (s) =>
                  s.productLocalId.equals(productId) &
                  s.locationLocalId.equals(locationId),
            ))
          .getSingle();

      expect(stockRow.currentStock, initialStock - 3);
    });

    test('enqueues exactly one high-priority sync task', () async {
      final result = await repository.createSale(draftWithOneItem());

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'sale');
      expect(queued.single.operation, 'create');
      expect(queued.single.entityLocalId, result.localId);
      expect(queued.single.priority, SyncPriority.salesAndPayments);
    });

    test('never touches the network — verified by absence, not a mock',
        () async {
      // No ApiClient/SalesApi is even constructed in this test's setUp.
      // If createSale awaited a network call, this test would have
      // nothing to hand it — the test passing at all is itself the
      // proof, not a separate assertion to write.
      await expectLater(
        repository.createSale(draftWithOneItem()),
        completes,
      );
    });

    // Regression coverage for a confirmed business-logic bug found
    // during audit: createSale wrote a correct Sale.balanceDue/
    // paymentStatus (both computed getters) but never told
    // CustomerCreditRepository about a credit sale at all —
    // Customer.outstandingBalance, the field every ledger/repayment/
    // credit-limit screen actually reads, simply never moved.
    // recordCreditSale itself was already fully implemented and
    // covered by customer_credit_repository_test.dart; what was
    // missing was ever calling it from here.
    group('credit sale / customer balance (bug fix regression)', () {
      Future<String> createTestCustomer() async {
        final customer = await customerRepository.createCustomer(
          const CustomerDraft(name: 'Chidinma Okafor'),
        );
        return customer.localId;
      }

      test('a sale left fully unpaid raises the balance by the full total',
          () async {
        final customerId = await createTestCustomer();
        final item = SaleItem(
          localId: 'item-credit-1',
          productLocalId: productId,
          quantity: 3,
          unitPrice: 150,
          costPriceAtSale: 100,
        );
        final draft = SaleDraft(
          items: [item],
          locationId: locationId,
          customerId: customerId,
          amountPaid: 0,
        );

        final sale = await repository.createSale(draft);

        expect(sale.total, 450);
        expect(sale.balanceDue, 450);
        final customer = await customerRepository.getCustomerById(customerId);
        expect(customer!.outstandingBalance, 450);
      });

      test(
          'a sale part-paid in cash then put on credit raises the balance '
          'by only the remainder, not the full total', () async {
        final customerId = await createTestCustomer();
        final item = SaleItem(
          localId: 'item-credit-2',
          productLocalId: productId,
          quantity: 3,
          unitPrice: 150,
          costPriceAtSale: 100,
        );
        // ₦450 total, ₦200 paid in cash up front — matches how
        // PaymentScreen's "Put Remaining on Account" leaves whatever
        // cash legs were already added in place.
        final draft = SaleDraft(
          items: [item],
          locationId: locationId,
          customerId: customerId,
          amountPaid: 200,
        );

        final sale = await repository.createSale(draft);

        expect(sale.total, 450);
        expect(sale.balanceDue, 250);
        final customer = await customerRepository.getCustomerById(customerId);
        // The bug this guards against: naively recording sale.total
        // (450) instead of sale.balanceDue (250) would double-count
        // the ₦200 already paid in cash.
        expect(customer!.outstandingBalance, 250);
      });

      test('a fully-paid sale with a customer attached does not touch '
          'the balance', () async {
        final customerId = await createTestCustomer();
        final draft = SaleDraft(
          items: [
            SaleItem(
              localId: 'item-credit-3',
              productLocalId: productId,
              quantity: 2,
              unitPrice: 150,
              costPriceAtSale: 100,
            ),
          ],
          locationId: locationId,
          customerId: customerId,
          amountPaid: 300,
        );

        final sale = await repository.createSale(draft);

        expect(sale.balanceDue, 0);
        final customer = await customerRepository.getCustomerById(customerId);
        expect(customer!.outstandingBalance, 0);
        final ledgerEntries =
            await db.select(db.customerLedgerEntries).get();
        expect(ledgerEntries, isEmpty);
      });

      test('a fully-paid sale with no customer attached never calls the '
          'credit ledger at all', () async {
        // Guards the null-customerId branch — the ordinary cash-sale
        // case every other test in this file already exercises;
        // asserted explicitly here since it's the one this fix's own
        // null check depends on.
        await repository.createSale(draftWithOneItem());

        final ledgerEntries =
            await db.select(db.customerLedgerEntries).get();
        expect(ledgerEntries, isEmpty);
      });

      test('two separate credit sales for the same customer accumulate',
          () async {
        final customerId = await createTestCustomer();
        SaleDraft creditDraftForItem(String itemId) => SaleDraft(
              items: [
                SaleItem(
                  localId: itemId,
                  productLocalId: productId,
                  quantity: 1,
                  unitPrice: 150,
                  costPriceAtSale: 100,
                ),
              ],
              locationId: locationId,
              customerId: customerId,
              amountPaid: 0,
            );

        await repository.createSale(creditDraftForItem('item-credit-4a'));
        await repository.createSale(creditDraftForItem('item-credit-4b'));

        final customer = await customerRepository.getCustomerById(customerId);
        expect(customer!.outstandingBalance, 300);
      });
    });
  });

  group('getSaleByLocalId', () {
    test('returns the sale with its items after creation', () async {
      final created = await repository.createSale(draftWithOneItem());

      final fetched = await repository.getSaleByLocalId(created.localId);

      expect(fetched, isNotNull);
      expect(fetched!.localId, created.localId);
      expect(fetched.items, hasLength(1));
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getSaleByLocalId('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('watchSalesForToday', () {
    test('emits the sale just created, scoped to its location',
        () async {
      final created = await repository.createSale(draftWithOneItem());

      final emitted = await repository.watchSalesForToday(locationId).first;

      expect(emitted.map((s) => s.localId), contains(created.localId));
    });

    test('does not emit sales from a different location', () async {
      await repository.createSale(draftWithOneItem());

      final emitted =
          await repository.watchSalesForToday('some-other-location').first;

      expect(emitted, isEmpty);
    });
  });

  group('getSalesForPeriod', () {
    test('includes a sale dated today when the period covers today', () async {
      final created = await repository.createSale(draftWithOneItem());

      final today = DateTime.now();
      final results = await repository.getSalesForPeriod(
        locationId: locationId,
        start: today,
        end: today,
      );

      expect(results.map((s) => s.localId), contains(created.localId));
      // getSalesForPeriod also returns each sale's items, same as
      // getSaleByLocalId — not just the bare Sale row.
      final match = results.firstWhere((s) => s.localId == created.localId);
      expect(match.items, hasLength(1));
    });

    test('excludes a sale outside the requested range', () async {
      await repository.createSale(draftWithOneItem());

      final farFuture = DateTime.now().add(const Duration(days: 365));
      final results = await repository.getSalesForPeriod(
        locationId: locationId,
        start: farFuture,
        end: farFuture,
      );

      expect(results, isEmpty);
    });

    test('excludes a sale from a different location', () async {
      await repository.createSale(draftWithOneItem());

      final today = DateTime.now();
      final results = await repository.getSalesForPeriod(
        locationId: 'some-other-location',
        start: today,
        end: today,
      );

      expect(results, isEmpty);
    });
  });

  group('markSynced', () {
    test('sets serverId, invoiceNumber, and syncStatus on the local row',
        () async {
      final created = await repository.createSale(draftWithOneItem());

      await repository.markSynced(
        localId: created.localId,
        serverId: 'server-abc',
        invoiceNumber: 'INV-001',
      );

      final row = await (db.select(db.sales)
            ..where((s) => s.localId.equals(created.localId)))
          .getSingle();

      expect(row.serverId, 'server-abc');
      expect(row.invoiceNumber, 'INV-001');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
}
