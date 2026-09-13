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

  test('rejects unsupported snapshot versions', () async {
    expect(
      () => CloudRestoreImporter(db).importSnapshot({'version': 2}),
      throwsA(isA<FormatException>()),
    );
  });
}
