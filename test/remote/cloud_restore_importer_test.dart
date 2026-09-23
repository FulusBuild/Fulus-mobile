import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/cloud_restore_importer.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('restores staff identity and mapped permissions', () async {
    final snapshot = <String, dynamic>{
      'version': 3,
      'membership': {'user_id': 'owner-1'},
      'business_memberships': [
        {
          'id': 'membership-1',
          'user_id': 'owner-1',
          'role_id': 'role-owner',
          'status': 'active',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'membership-2',
          'user_id': 'staff-1',
          'role_id': 'role-manager',
          'status': 'active',
          'created_at': '2026-01-02T00:00:00Z',
          'updated_at': '2026-01-02T00:00:00Z',
        },
      ],
      'profiles': [
        {'id': 'staff-1', 'full_name': 'Staff Member', 'phone': '08000000000'},
      ],
      'roles': [
        {'id': 'role-manager', 'name': 'manager'},
      ],
      'permissions': [
        {'id': 'perm-reports', 'code': 'reports.read'},
        {'id': 'perm-employees', 'code': 'employees.manage'},
      ],
      'role_permissions': [
        {'role_id': 'role-manager', 'permission_id': 'perm-reports'},
        {'role_id': 'role-manager', 'permission_id': 'perm-employees'},
      ],
      'location_memberships': [],
      'locations': [],
      'categories': [],
      'suppliers': [],
      'customers': [],
      'products': [],
      'sales': [],
      'sale_items': [],
      'sale_payments': [],
      'product_stock_levels': [],
      'customer_ledger_entries': [],
      'inventory_movements': [],
      'expense_categories': [],
      'expenses': [],
      'income_records': [],
      'returns': [],
      'return_items': [],
      'tax_remittances': [],
      'cash_drawer_shifts': [],
      'audit_events': [],
    };

    final result = await CloudRestoreImporter(db).importSnapshot(
      snapshot,
      ownerCloudUserId: 'owner-1',
    );

    expect(result.importedCounts['restored_staff_users'], 1);
    expect(result.importedCounts['restored_employees'], 1);
    expect(result.importedCounts['restored_user_permissions'], 2);

    final users = await db.select(db.users).get();
    final employees = await db.select(db.employees).get();
    final permissions = await db.select(db.userPermissions).get();

    expect(users.single.localId, 'staff-1');
    expect(users.single.fullName, 'Staff Member');
    expect(employees.single.authUserId, 'staff-1');
    expect(employees.single.role, 'manager');
    expect(permissions.map((row) => row.permission.name), containsAll(<String>['viewReports', 'manageEmployees']));
  });

  test('restores cashier users before sales with cashier foreign keys', () async {
    final now = DateTime(2026, 9, 23);
    await db.into(db.users).insert(
      UsersCompanion.insert(
        localId: 'owner-1',
        fullName: 'Business Owner',
        role: AuthRole.owner,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final snapshot = <String, dynamic>{
      'version': 6,
      'business_memberships': [
        {
          'id': 'membership-owner',
          'user_id': 'owner-1',
          'role_id': 'role-owner',
          'status': 'active',
        },
        {
          'id': 'membership-cashier',
          'user_id': 'cashier-1',
          'role_id': 'role-cashier',
          'status': 'active',
        },
      ],
      'profiles': [
        {'id': 'cashier-1', 'full_name': 'Cashier One'},
      ],
      'roles': [
        {'id': 'role-cashier', 'name': 'cashier'},
      ],
      'permissions': [],
      'role_permissions': [],
      'location_memberships': [
        {
          'user_id': 'cashier-1',
          'location_id': 'location-1',
          'status': 'active',
        },
      ],
      'locations': [
        {'id': 'location-1', 'name': 'Main'},
      ],
      'categories': [],
      'suppliers': [],
      'customers': [],
      'products': [],
      'sales': [
        {
          'id': 'sale-owner',
          'client_reference': 'sale-owner',
          'location_id': 'location-1',
          'cashier_user_id': 'owner-1',
          'sale_date': '2026-09-23T10:00:00Z',
          'subtotal': 100,
          'total': 100,
          'amount_paid': 100,
        },
        {
          'id': 'sale-cashier',
          'client_reference': 'sale-cashier',
          'location_id': 'location-1',
          'cashier_user_id': 'cashier-1',
          'sale_date': '2026-09-23T10:01:00Z',
          'subtotal': 200,
          'total': 200,
          'amount_paid': 200,
        },
      ],
      'sale_items': [],
      'sale_payments': [],
      'product_stock_levels': [],
      'customer_ledger_entries': [],
      'inventory_movements': [],
      'expense_categories': [],
      'expenses': [],
      'income_records': [],
      'supplier_ledger_entries': [],
      'returns': [],
      'return_items': [],
      'tax_remittances': [],
      'cash_drawer_shifts': [],
      'audit_events': [],
    };

    await CloudRestoreImporter(db).importSnapshot(
      snapshot,
      ownerCloudUserId: 'owner-1',
    );

    final users = await db.select(db.users).get();
    final sales = await db.select(db.sales).get();

    expect(users.map((row) => row.localId), containsAll(<String>['owner-1', 'cashier-1']));
    expect(sales.map((row) => row.cashierUserId), containsAll(<String>['owner-1', 'cashier-1']));
  });

  test('translates cloud inventory movement deltas into local movement schema', () async {
    final snapshot = <String, dynamic>{
      'version': 6,
      'locations': [
        {'id': 'location-1', 'name': 'Main'},
      ],
      'products': [
        {
          'id': 'product-1',
          'name': 'Test product',
          'sku': 'TEST-1',
          'cost_price': 10,
          'selling_price': 20,
          'low_stock_threshold': 2,
          'is_active': true,
          'tracks_stock': true,
        },
      ],
      'inventory_movements': [
        {
          'id': 'movement-adjust',
          'product_id': 'product-1',
          'location_id': 'location-1',
          'quantity_delta': 7,
          'current_stock': 12,
          'operation_type': 'inventory.set',
          'reason': 'Physical count',
          'operation_id': 'op-adjust',
          'created_at': '2026-09-22T10:00:00Z',
        },
        {
          'id': 'movement-sale',
          'product_id': 'product-1',
          'location_id': 'location-1',
          'quantity_delta': -3,
          'reason': 'sale INV-1',
          'operation_id': 'op-sale',
          'created_at': '2026-09-22T10:01:00Z',
        },
      ],
    };

    await CloudRestoreImporter(db).importSnapshot(snapshot);

    final rows = await db.select(db.stockMovements).get();
    final adjustment = rows.singleWhere((row) => row.localId == 'movement-adjust');
    final sale = rows.singleWhere((row) => row.localId == 'movement-sale');

    expect(adjustment.movementType, 'adjustment');
    expect(adjustment.newQuantity, 12);
    expect(adjustment.quantity, isNull);
    expect(sale.movementType, 'sale');
    expect(sale.quantity, 3);
    expect(sale.newQuantity, isNull);
  });

  test('normalizes sale payments, legacy returns, and nullable expense descriptions', () async {
    final snapshot = <String, dynamic>{
      'version': 6,
      'locations': [
        {'id': 'location-1', 'name': 'Main'},
      ],
      'products': [
        {
          'id': 'product-1',
          'name': 'Test product',
          'sku': 'TEST-1',
          'cost_price': 10,
          'selling_price': 20,
        },
      ],
      'customers': [
        {
          'id': 'customer-1',
          'name': 'Customer One',
          'phone': '08000000001',
        },
      ],
      'sales': [
        {
          'id': 'sale-1',
          'client_reference': 'sale-1',
          'location_id': 'location-1',
          'sale_date': '2026-09-22T10:00:00Z',
          'subtotal': 20,
          'total': 20,
        },
      ],
      'sale_items': [
        {
          'id': 'sale-item-1',
          'sale_id': 'sale-1',
          'product_id': 'product-1',
          'quantity': 1,
          'unit_price': 20,
          'cost_price_at_sale': 10,
        },
      ],
      'sale_payments': [
        {
          'id': 'payment-1',
          'sale_id': 'sale-1',
          'amount': 20,
          'payment_method': 'cash',
          'created_at': '2026-09-22T10:01:00Z',
        },
      ],
      'customer_ledger_entries': [
        {
          'id': 'ledger-1',
          'customer_id': 'customer-1',
          'sale_id': 'sale-1',
          'entry_type': 'creditSale',
          'amount': 20,
          'operation_id': 'ledger-op-1',
          'created_at': '2026-09-22T10:01:30Z',
        },
      ],
      'expenses': [
        {
          'id': 'expense-1',
          'location_id': 'location-1',
          'amount': 100,
          'category': 'General',
          'description': null,
          'expense_date': '2026-09-22T10:02:00Z',
        },
      ],
      'returns': [
        {
          'id': 'return-1',
          'sale_id': 'sale-1',
          'client_reference': 'return-1',
          'reason': 'Damaged',
          'refund_amount': 20,
          'status': 'completed',
          'created_at': '2026-09-22T10:03:00Z',
        },
      ],
      'return_items': [
        {
          'id': 'return-item-1',
          'return_id': 'return-1',
          'sale_item_id': 'sale-item-1',
          'product_id': 'product-1',
          'quantity': 1,
          'amount': 20,
        },
      ],
    };

    await CloudRestoreImporter(db).importSnapshot(snapshot);

    final saleItem = (await db.select(db.saleItems).get()).single;
    expect(saleItem.saleLocalId, 'sale-1');
    expect(saleItem.productLocalId, 'product-1');

    final payment = (await db.select(db.salePayments).get()).single;
    expect(payment.method, 'cash');
    expect(payment.recordedAt, DateTime.parse('2026-09-22T10:01:00Z').toLocal());

    final ledger = (await db.select(db.customerLedgerEntries).get()).single;
    expect(ledger.customerLocalId, 'customer-1');
    expect(ledger.saleLocalId, 'sale-1');

    final expense = (await db.select(db.expenses).get()).single;
    expect(expense.description, '');

    final returnRow = (await db.select(db.returnRequests).get()).single;
    expect(returnRow.originalSaleLocalId, 'sale-1');
    expect(returnRow.returnReason, 'Damaged');
    expect(returnRow.refundMethod, 'cash');
    expect(returnRow.inventoryRestored, isTrue);
    expect(returnRow.isVoid, isFalse);

    final returnItem = (await db.select(db.returnItems).get()).single;
    expect(returnItem.returnLocalId, 'return-1');
    expect(returnItem.productLocalId, 'product-1');
  });

  test('rejects unsupported snapshot versions', () async {
    expect(
      () => CloudRestoreImporter(db).importSnapshot({'version': 2}),
      throwsA(isA<FormatException>()),
    );
  });
}
