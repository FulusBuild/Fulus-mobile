import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/cloud_restore_importer.dart';

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
      'supplier_ledger_entries': [],
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

  test('rejects unsupported snapshot versions', () async {
    expect(
      () => CloudRestoreImporter(db).importSnapshot({'version': 2}),
      throwsA(isA<FormatException>()),
    );
  });
}
