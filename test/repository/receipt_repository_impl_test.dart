import 'package:fulus_mobile/core/errors/module_failures.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/receipt_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_seed_helpers.dart';

/// **Phase 0 completion pass.** No test existed for this repository
/// before this pass — included specifically because this pass replaced
/// a hardcoded `cashierName: null` with a real Users lookup, and
/// "verify every fix" means this file needs its first real test.
void main() {
  late AppDatabase db;
  late ReceiptRepositoryImpl repository;

  const locationId = 'loc-1';
  final now = DateTime.now();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ReceiptRepositoryImpl(db: db);

    await db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ));
    await db.into(db.businessSettings).insert(BusinessSettingsCompanion.insert(
          id: 'singleton',
          businessName: 'Test Shop',
          updatedAt: now,
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          localId: 'p1',
          name: 'Rice 5kg',
          sku: 'RICE-5KG',
          costPrice: 2000,
          sellingPrice: 2500,
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSale({String? cashierUserId}) async {
    await db.into(db.sales).insert(SalesCompanion.insert(
          localId: 'sale-1',
          clientReference: 'sale-1',
          locationId: locationId,
          cashierUserId: Value(cashierUserId),
          saleDate: now,
          subtotal: 2500,
          total: 2500,
          amountPaid: const Value(2500),
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
          localId: 'item-1',
          saleLocalId: 'sale-1',
          productLocalId: const Value('p1'),
          quantity: 1,
          unitPrice: 2500,
          costPriceAtSale: 2000,
        ));
  }

  group('buildReceiptData — cashierName', () {
    test('resolves the real cashier name when cashierUserId is set', () async {
      await db.into(db.users).insert(UsersCompanion.insert(
            localId: 'u1',
            username: 'amaka',
            email: 'amaka@example.com',
            fullName: 'Amaka Okafor',
            hashedPassword: 'irrelevant-for-this-test',
            passwordSalt: 'irrelevant-for-this-test',
            role: AuthRole.employee,
            createdAt: now,
            updatedAt: now,
          ));
      await seedSale(cashierUserId: 'u1');

      final receipt = await repository.buildReceiptData('sale-1');

      expect(receipt.cashierName, 'Amaka Okafor');
    });

    test('is null, not an error, for a sale with no cashierUserId', () async {
      await seedSale(); // no cashierUserId

      final receipt = await repository.buildReceiptData('sale-1');

      expect(receipt.cashierName, isNull);
    });

    test('is null when cashierUserId points at a user that no longer exists', () async {
      // A dangling cashierUserId can't be produced through a normal
      // FK-enforced insert — this simulates the real-world case (a
      // user row deleted after the sale was made) by relaxing FK
      // enforcement for just this one seed.
      await withoutForeignKeyChecks(db, () => seedSale(cashierUserId: 'does-not-exist'));

      final receipt = await repository.buildReceiptData('sale-1');

      expect(receipt.cashierName, isNull);
    });
  });

  group('buildReceiptData — general shape', () {
    test('includes the business name and line items', () async {
      await seedSale();

      final receipt = await repository.buildReceiptData('sale-1');

      expect(receipt.businessName, 'Test Shop');
      expect(receipt.items, hasLength(1));
      expect(receipt.items.single.productName, 'Rice 5kg');
      expect(receipt.total, 2500);
    });

    test('throws ReceiptDataUnavailable for a sale that does not exist', () async {
      expect(
        () => repository.buildReceiptData('does-not-exist'),
        throwsA(isA<ReceiptDataUnavailable>()),
      );
    });
  });
}
