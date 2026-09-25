import 'package:drift/drift.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/business_category.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/entities/permission.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/business_settings_repository.dart';
import '../../domain/repositories/permission_repository.dart';
import '../local/database/database.dart';
import '../remote/endpoints/business_settings_api.dart';
import 'business_settings_mapper.dart';
import '../../sync/sync_execution_lease.dart';

class BusinessSettingsRepositoryImpl implements BusinessSettingsRepository {
  BusinessSettingsRepositoryImpl({
    required AppDatabase db,
    required BusinessSettingsApi businessSettingsApi,
    required AuthRepository authRepository,
    required PermissionRepository permissionRepository,
    required SyncExecutionLease executionLease,
  })  : _db = db,
        _businessSettingsApi = businessSettingsApi,
        _authRepository = authRepository,
        _permissionRepository = permissionRepository,
        _executionLease = executionLease;

  final AppDatabase _db;
  final BusinessSettingsApi _businessSettingsApi;
  // Depends on AuthRepository directly (unlike AuditRepository, which
  // takes the caller's role as a plain parameter instead) — no cycle
  // risk here, since nothing AuthRepositoryImpl depends on depends back
  // on this class, so there's no reason to push the role-lookup out to
  // every call site the way Audit's genuine circular dependency forced.
  // Same reasoning covers the added PermissionRepository dependency
  // below.
  final AuthRepository _authRepository;
  final PermissionRepository _permissionRepository;
  final SyncExecutionLease _executionLease;

  @override
  Stream<BusinessProfile?> watchSettings() {
    final query = _db.select(_db.businessSettings)
      ..where((s) => s.id.equals('singleton'));
    return query.watchSingleOrNull().map((row) => row?.toDomain());
  }

  @override
  Future<bool> hasBeenConfigured() async {
    final existing = await (_db.select(_db.businessSettings)
          ..where((s) => s.id.equals('singleton')))
        .getSingleOrNull();
    return existing != null;
  }

  @override
  Future<void> createBusiness({
    required String businessName,
    required BusinessCategory category,
    required String currencySymbol,
  }) async {
    if (await hasBeenConfigured()) {
      throw const BusinessRuleFailure(
        'This business has already been set up on this device.',
      );
    }

    _validateBusinessName(businessName);
    _validateCurrencySymbol(currencySymbol);

    final defaults = BusinessCategoryDefaults.forCategory(category);

    await _db.into(_db.businessSettings).insert(
          BusinessSettingsCompanion.insert(
            id: 'singleton',
            businessName: businessName,
            currencySymbol: Value(currencySymbol),
            vatEnabled: Value(defaults.vatEnabled),
            vatRate: Value(defaults.vatRate),
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> updateSettings({
    required String businessName,
    String? address,
    String? phone,
    String? email,
    String? tin,
    required bool vatEnabled,
    required double vatRate,
    required String currencySymbol,
    String? receiptFooter,
  }) async {
    // The local check IS the real enforcement now — see
    // AuthFailure.forbidden's doc comment in failure.dart. Roles &
    // Permissions (schemaVersion 10): was a raw `role != AuthRole.owner`
    // check; now it's Permission.manageSettings, which an owner always
    // has (the usual structural exemption) and a Manager can now be
    // granted too.
    final user = _authRepository.currentUser;
    final allowed = user != null &&
        await _permissionRepository.hasPermission(
          userId: user.id,
          role: user.role,
          permission: Permission.manageSettings,
        );
    if (!allowed) {
      throw const AuthFailure.forbidden();
    }

    _validateBusinessName(businessName);
    _validateCurrencySymbol(currencySymbol);
    // Mirrors schemas/settings.py's Field(ge=0, le=100) exactly —
    // verified directly.
    if (vatRate < 0 || vatRate > 100) {
      throw const ValidationFailure(
        fieldErrors: {'vatRate': 'VAT rate must be between 0 and 100.'},
      );
    }

    await (_db.update(_db.businessSettings)
          ..where((s) => s.id.equals('singleton')))
        .write(
      BusinessSettingsCompanion(
        businessName: Value(businessName),
        address: Value(address),
        phone: Value(phone),
        email: Value(email),
        tin: Value(tin),
        vatEnabled: Value(vatEnabled),
        vatRate: Value(vatRate),
        currencySymbol: Value(currencySymbol),
        receiptFooter: Value(receiptFooter),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Verified directly: routers/settings.py's PUT endpoint has no
    // audit_service.log() call at all — none of the other 55 real call
    // sites are for settings updates. No audit entry added here either,
    // matching what the real system actually does rather than assuming
    // every mutation should be audited just because Stage 3 exists now.
  }

  @override
  Future<void> syncFromServer() async {
    // A single object, not a list — unlike LocationRepositoryImpl's
    // syncFromServer, there's nothing to iterate here.
    // insertOnConflictUpdate for the same reason as Location's own
    // choice over InsertMode.insertOrReplace, even though nothing
    // currently references BusinessSettings.id by foreign key the way
    // Locations.localId is referenced everywhere: consistency with the
    // established convention, not a response to a concrete risk here.
    //
    // Still genuinely useful post-redesign, not vestigial: a Host
    // scenario (Sync layer, deferred) is exactly the case where a
    // second device's locally-created settings should converge with
    // whatever the Host considers authoritative — this just isn't the
    // ONLY way a row gets created anymore, per createBusiness above.
    final response = await _businessSettingsApi.getBusinessProfile();
    await _db.into(_db.businessSettings).insertOnConflictUpdate(response.toDriftCompanion());
  }

  @override
  Future<void> clearLocalBusinessData() async {
    await _executionLease.acquire();
    try {
    // One transaction, children deleted before parents — `beforeOpen`
    // (database.dart) turns on `PRAGMA foreign_keys = ON`, so this
    // order is load-bearing, not cosmetic. Built directly against every
    // `references()` declaration in tables.dart/employee_tables.dart at
    // the time this was written: SaleItems/SalePayments/
    // CustomerLedgerEntries/ReturnRequests -> Sales; ReturnItems ->
    // ReturnRequests + Products; DraftCartItems/DraftCartPayments ->
    // DraftCarts; DraftCarts -> Locations; StockMovements/
    // ProductStockLevels -> Products + Locations; SupplierLedgerEntries
    // -> Suppliers; TaxRemittances/CashDrawerShifts -> Locations;
    // Sales -> Locations + Users; AttendanceRecords/LeaveRecords ->
    // Employees; Employees/LeaveRecords/Sessions -> Users. Anything not
    // referenced by another table (AuditLogs, AppNotifications,
    // PairedPrinters, SyncQueueItems, ExpenseCategories, Expenses,
    // IncomeRecords, Categories) can go in any order, grouped up front.
    await _db.transaction(() async {
      await _db.delete(_db.saleItems).go();
      await _db.delete(_db.salePayments).go();
      await _db.delete(_db.customerLedgerEntries).go();
      await _db.delete(_db.returnItems).go();
      await _db.delete(_db.draftCartItems).go();
      await _db.delete(_db.draftCartPayments).go();
      await _db.delete(_db.supplierLedgerEntries).go();
      await _db.delete(_db.taxRemittances).go();
      await _db.delete(_db.cashDrawerShifts).go();
      await _db.delete(_db.stockMovements).go();
      await _db.delete(_db.productStockLevels).go();
      await _db.delete(_db.attendanceRecords).go();
      await _db.delete(_db.leaveRecords).go();
      await _db.delete(_db.auditLogs).go();
      await _db.delete(_db.appNotifications).go();
      await _db.delete(_db.pairedPrinters).go();
      await _db.delete(_db.syncQueueItems).go();
      await _db.delete(_db.expenseCategories).go();
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.incomeRecords).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.returnRequests).go();
      await _db.delete(_db.draftCarts).go();
      await _db.delete(_db.employees).go();
      await _db.delete(_db.suppliers).go();
      await _db.delete(_db.customers).go();
      await _db.delete(_db.sales).go();
      await _db.delete(_db.products).go();
      await _db.delete(_db.sessions).go();
      await _db.delete(_db.users).go();
      await _db.delete(_db.locations).go();
      await _db.delete(_db.businessSettings).go();
    });
    } finally {
      await _executionLease.release();
    }
  }

  void _validateBusinessName(String businessName) {
    // Mirrors schemas/settings.py's Field(min_length=1, max_length=150)
    // exactly — verified directly.
    if (businessName.isEmpty || businessName.length > 150) {
      throw const ValidationFailure(
        fieldErrors: {
          'businessName': 'Business name must be between 1 and 150 characters.',
        },
      );
    }
  }

  void _validateCurrencySymbol(String currencySymbol) {
    // Mirrors schemas/settings.py's Field(min_length=1, max_length=5)
    // exactly — verified directly.
    if (currencySymbol.isEmpty || currencySymbol.length > 5) {
      throw const ValidationFailure(
        fieldErrors: {
          'currencySymbol': 'Currency symbol must be between 1 and 5 characters.',
        },
      );
    }
  }
}
