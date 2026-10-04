import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/local/database/database.dart';
import '../../lib/data/remote/cross_device_employee_restore.dart';
import '../../lib/data/remote/fulus_staff_access_api.dart';
import '../../lib/domain/entities/auth_user.dart';
import '../../lib/domain/entities/business_settings.dart';
import '../../lib/sync/sync_execution_lease.dart';

void main() {
  late AppDatabase db;
  late SyncExecutionLease lease;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    lease = SyncExecutionLease(db);
  });

  tearDown(() async {
    await lease.release();
    await db.close();
  });

  test('employee restore preserves historical cashier foreign keys without importing staff identities', () async {
    const employeeId = 'employee-1';
    final restore = CrossDeviceEmployeeRestore(db, executionLease: lease);

    final claim = StaffClaim(
      businessId: 'business-1',
      membershipId: 'membership-1',
      userId: employeeId,
      roleId: 'role-cashier',
      roleName: 'cashier',
      fullName: 'Current Employee',
      email: 'employee@example.com',
      locationId: 'location-1',
      permissionCodes: const [],
      employeeId: 'employee-record-1',
      employee: const {
        'id': 'employee-record-1',
        'full_name': 'Current Employee',
        'role': 'cashier',
        'location_id': 'location-1',
        'is_active': true,
      },
    );

    final snapshot = <String, dynamic>{
      'version': 7,
      'business': {
        'id': 'business-1',
        'name': 'Test Store',
        'currency_code': 'NGN',
        'vat_enabled': false,
        'vat_rate': 0,
      },
      'membership': {
        'business_id': 'business-1',
        'user_id': employeeId,
        'role_id': 'role-cashier',
        'status': 'active',
        'role_name': 'cashier',
      },
      'profile': {
        'id': employeeId,
        'full_name': 'Current Employee',
        'email': 'employee@example.com',
      },
      'business_memberships': [
        {
          'id': 'membership-1',
          'user_id': employeeId,
          'role_id': 'role-cashier',
          'status': 'active',
        },
      ],
      'profiles': [
        {
          'id': employeeId,
          'full_name': 'Current Employee',
          'email': 'employee@example.com',
        },
      ],
      'roles': [],
      'permissions': [],
      'role_permissions': [],
      'business_member_permissions': [],
      'location_memberships': [
        {
          'user_id': employeeId,
          'location_id': 'location-1',
          'status': 'active',
        },
      ],
      'locations': [
        {'id': 'location-1', 'name': 'Main'},
      ],
      'employees': [
        {
          'id': 'employee-record-1',
          'membership_id': 'membership-1',
          'auth_user_id': employeeId,
          'full_name': 'Current Employee',
          'role': 'cashier',
          'location_id': 'location-1',
          'is_active': true,
        },
      ],
      'categories': [],
      'suppliers': [],
      'customers': [],
      'products': [
        {
          'id': 'product-1',
          'name': 'Rice',
          'sku': 'RICE-1',
          'price': 1000,
          'cost_price': 800,
          'stock_quantity': 10,
        },
      ],
      'sales': [
        {
          'id': 'sale-old-cashier',
          'client_reference': 'sale-old-cashier',
          'location_id': 'location-1',
          'cashier_user_id': 'former-cashier-1',
          'sale_date': '2026-09-23T10:00:00Z',
          'subtotal': 1000,
          'total': 1000,
          'amount_paid': 1000,
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
      'returns': [],
      'return_items': [],
      'tax_remittances': [],
      'cash_drawer_shifts': [],
      'audit_events': [],
    };

    await restore.restore(
      snapshot: snapshot,
      claim: claim,
      settings: const BusinessSettingsResponseDto(
        id: 'business-1',
        businessName: 'Test Store',
        vatEnabled: false,
        vatRate: 0,
        currencySymbol: '₦',
      ),
      role: AuthRole.cashier,
    );

    final users = await db.select(db.users).get();
    final sales = await db.select(db.sales).get();

    expect(sales.single.cashierUserId, 'former-cashier-1');
    final historical = users.singleWhere((user) => user.localId == 'former-cashier-1');
    expect(historical.isActive, isFalse);
    expect(historical.fullName, 'Historical staff');
    expect(users.where((user) => user.isActive).map((user) => user.localId), [employeeId]);
  });
}
