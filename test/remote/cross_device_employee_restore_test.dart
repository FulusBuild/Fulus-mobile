import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/local/database/database.dart';
import '../../lib/domain/entities/auth_user.dart';
import '../../lib/data/remote/cross_device_employee_restore.dart';
import '../../lib/data/remote/fulus_staff_access_api.dart';
import '../../lib/sync/sync_execution_lease.dart';

void main() {
  late AppDatabase db;
  late SyncExecutionLease executionLease;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    executionLease = SyncExecutionLease(db);
  });

  tearDown(() async {
    await executionLease.release();
    await db.close();
  });

  test('seeds inactive historical cashier identities before importing sales on a fresh employee device', () async {
    const employeeId = 'employee-user-id';
    const ownerId = 'business-owner-user-id';

    final snapshot = <String, dynamic>{
      'version': 7,
      'business': {
        'id': 'business-1',
        'name': 'Test Store',
        'currency_code': 'NGN',
      },
      // Employee snapshots deliberately include only the claimed employee's
      // membership/profile, not the owner's or full staff roster.
      'business_memberships': [
        {
          'id': 'membership-employee',
          'business_id': 'business-1',
          'user_id': employeeId,
          'role_id': 'role-cashier',
          'status': 'active',
        },
      ],
      'profiles': [
        {'id': employeeId, 'full_name': 'Test Employee'},
      ],
      'roles': [
        {'id': 'role-cashier', 'name': 'cashier'},
      ],
      'permissions': [],
      'role_permissions': [],
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
      'categories': [],
      'suppliers': [],
      'customers': [],
      'products': [],
      'sales': [
        {
          'id': 'sale-owned-by-owner',
          'client_reference': 'sale-owned-by-owner',
          'location_id': 'location-1',
          'cashier_user_id': ownerId,
          'sale_date': '2026-10-09T10:00:00Z',
          'subtotal': '100.00',
          'total': '100.00',
          'amount_paid': '100.00',
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

    final claim = StaffClaim(
      businessId: 'business-1',
      membershipId: 'membership-employee',
      userId: employeeId,
      roleId: 'role-cashier',
      roleName: 'cashier',
      fullName: 'Test Employee',
      email: 'employee@example.com',
      locationId: 'location-1',
      permissionCodes: const [],
      employeeId: 'employee-1',
      employee: const {
        'full_name': 'Test Employee',
        'role': 'cashier',
        'location_id': 'location-1',
        'email': 'employee@example.com',
      },
    );

    await CrossDeviceEmployeeRestore(
      db,
      executionLease: executionLease,
    ).restore(
      snapshot: snapshot,
      claim: claim,
      settings: CrossDeviceEmployeeRestore.settingsFromSnapshot(snapshot),
      role: AuthRole.cashier,
    );

    final sales = await db.select(db.sales).get();
    expect(sales, hasLength(1));
    expect(sales.single.cashierUserId, ownerId);

    final historicalOwner = await (db.select(db.users)
          ..where((user) => user.localId.equals(ownerId)))
        .getSingle();
    expect(historicalOwner.isActive, isFalse);
    expect(historicalOwner.fullName, 'Historical staff member');

    final employee = await (db.select(db.users)
          ..where((user) => user.localId.equals(employeeId)))
        .getSingle();
    expect(employee.isActive, isTrue);

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
