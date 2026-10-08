import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/diagnostics/capture/current_screen_tracker.dart';
import '../core/onboarding/onboarding_routing.dart';
import '../core/theme/design_tokens.dart';
import '../core/theme/fulus_art.dart';
import '../domain/entities/auth_user.dart';
import '../domain/entities/customer.dart';
import '../domain/entities/permission.dart';
import '../domain/entities/product.dart';
import '../domain/entities/supplier.dart';
import '../features/auth/presentation/screens/auth_gate_screen.dart';
import '../features/auth/presentation/screens/employee_login_screen.dart';
import '../features/auth/presentation/screens/owner_setup_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/money/domain/cash_drawer_state.dart';
import '../features/money/domain/money_transaction.dart';
import '../features/money/presentation/screens/add_expense_screen.dart';
import '../features/money/presentation/screens/add_income_screen.dart';
import '../features/money/presentation/screens/archived_customers_screen.dart';
import '../features/money/presentation/screens/customer_profile_screen.dart';
import '../features/money/presentation/screens/customers_list_screen.dart';
import '../features/money/presentation/screens/daily_closing_count_screen.dart';
import '../features/money/presentation/screens/daily_closing_summary_screen.dart';
import '../features/money/presentation/screens/money_history_screen.dart';
import '../features/money/presentation/screens/money_screen.dart';
import '../features/money/presentation/screens/pay_supplier_screen.dart';
import '../features/money/presentation/screens/receipt_history_screen.dart';
import '../features/money/presentation/screens/record_repayment_screen.dart';
import '../features/money/presentation/screens/supplier_profile_screen.dart';
import '../features/money/presentation/screens/suppliers_list_screen.dart';
import '../features/money/presentation/screens/transaction_detail_screen.dart';
import '../features/more/employees/presentation/screens/deactivated_employees_screen.dart';
import '../features/more/diagnostics/presentation/screens/diagnostic_detail_screen.dart';
import '../features/more/diagnostics/presentation/screens/diagnostics_screen.dart';
import '../features/more/employees/presentation/screens/employee_detail_screen.dart';
import '../features/more/employees/presentation/screens/employees_list_screen.dart';
import '../features/more/presentation/screens/notifications_screen.dart';
import '../domain/entities/report.dart';
import '../features/more/reports/presentation/screens/reports_screen.dart';
import '../features/more/reports/presentation/screens/sales_transactions_screen.dart';
import '../features/more/settings/presentation/screens/backup_screen.dart';
import '../features/more/settings/presentation/screens/manage_locations_screen.dart';
import '../features/more/settings/presentation/screens/printer_pairing_screen.dart';
import '../features/more/settings/presentation/screens/settings_main_screen.dart';
import '../features/more/settings/presentation/screens/fulus_cloud_connection_screen.dart';
import '../features/more/settings/presentation/screens/sync_detail_screen.dart';
import '../features/onboarding/presentation/screens/add_first_product_screen.dart';
import '../features/onboarding/presentation/screens/essential_settings_screen.dart';
import '../features/onboarding/presentation/screens/first_run_setup_screen.dart';
import '../features/onboarding/presentation/screens/first_sale_intro_screen.dart';
import '../features/onboarding/presentation/screens/navigation_intro_screen.dart';
import '../features/sell/presentation/screens/refund_confirm_screen.dart';
import '../features/sell/presentation/screens/void_sale_screen.dart';
import '../features/sell/presentation/screens/refund_search_screen.dart';
import '../features/sell/presentation/screens/sell_screen.dart';
import '../features/stock/presentation/screens/add_edit_product_screen.dart';
import '../features/stock/presentation/screens/bulk_import_review_screen.dart';
import '../features/stock/presentation/screens/bulk_import_screen.dart';
import '../features/stock/presentation/screens/categories_screen.dart';
import '../features/stock/presentation/screens/product_detail_screen.dart';
import '../features/stock/presentation/screens/record_stock_movement_screen.dart';
import '../features/stock/presentation/screens/stock_movement_history_screen.dart';
import '../features/stock/presentation/screens/stock_screen.dart';
import '../shared/widgets/widgets.dart';
import 'app_shell.dart';
import 'providers.dart';

/// go_router configuration — Architecture Section 1 names this as its
/// own file under app/. Per the brief's rule against building temporary
/// solutions, this is a genuinely real router (real route names, real
/// go_router API), wired to real screens wherever one exists.
///
/// **Foundation phase 2 (App/Home shell + navigation)**: the five
/// top-level destinations (Home, Stock, Sell, Money, More) are now
/// `StatefulShellRoute.indexedStack` branches wrapped in
/// [FulusAppShell]'s persistent bottom nav (Component Library 5.5),
/// each keeping its own independent navigation stack — previously each
/// was a standalone top-level [GoRoute] with no shared chrome and no
/// visible way to move between them at all. Route paths and names are
/// unchanged from before this phase; only how they're grouped changed,
/// so nothing outside this file needed to change.
///
/// **Foundation phase 3 (Owner setup / sign-in)**: the entire shell is
/// gated behind [sessionProvider] rather than reading
/// `ref.watch(authRepositoryProvider).currentUser` directly — that
/// getter isn't reactive (see sessionProvider's own doc comment in
/// providers.dart for why watching it directly silently never rebuilds
/// after a real sign-in). The placeholder previously shown when signed
/// out is now [AuthGateScreen], a real, working owner-setup/sign-in
/// flow.
///
/// **Foundation follow-up (gap closure)**: two things phase 3 originally
/// flagged as open are closed now, both in [_ShellGate] below and this
/// `redirect`:
/// - An owner signed in with no business configured (app killed between
///   [OwnerSetupScreen]'s two underlying local calls — create the owner,
///   then create the business — in an earlier session) used to land
///   straight in the shell with nothing configured. [_ShellGate] now
///   checks [BusinessSettingsRepository.hasBeenConfigured] for a
///   signed-in owner and resumes [OwnerSetupScreen] at its business
///   fields instead, before ever building [FulusAppShell]. Onboarding-
///   simplification pass: those two calls sit behind one combined form
///   now, not two separate submits — see that screen's own doc comment
///   — but the interruption window between them is exactly the same.
/// - Employee sessions previously reached `/money` and everything under
///   `/more` exactly like an owner would (Volume 9: "never sees Money,
///   Reports, Employees, or Settings"). [FulusAppShell] hides those nav
///   buttons for an Employee session, but a hidden button alone isn't
///   real enforcement (failure.dart's own `_Forbidden` doc comment makes
///   this same point about permission checks generally) — the
///   `redirect` below is what actually blocks reaching those routes,
///   the same way a direct call bypassing the UI has to be rejected too.
///
/// **Roles & Permissions (schemaVersion 10)**: the blanket "Employee ⇒
/// blocked from `/money` and everything under `/more`" rule above is
/// gone — replaced with a real per-[Permission] check against
/// [PermissionRepository], same owner-is-structurally-exempt shortcut
/// that repository's own `hasPermission` applies. `redirect` is `async`
/// now (go_router's `GoRouterRedirect` has always allowed
/// `FutureOr<String?>`) specifically so this can await a real
/// permission lookup rather than relying on some other widget having
/// already warmed [sessionPermissionsProvider]'s cache by the time
/// navigation happens — the one thing actually gating a route should
/// never depend on unrelated UI having rendered first. `/more` itself
/// (the menu screen) and its Notifications/Diagnostics subroutes need
/// no permission at all now — see `_permissionForMoreRoute` below and
/// `_MoreScreen`'s own doc comment for why those two stayed
/// unrestricted even as everything else under `/more` became
/// individually gated.
///
/// **Foundation follow-up (Money)**: `/money` and everything under it
/// (History, Transaction Detail, Add Income/Expense, Customers/
/// Suppliers credit books, Daily Closing) are real screens now, not a
/// placeholder — see `features/money/` for the feature itself, and its
/// own doc comments for exactly which parts read real data versus this
/// feature's own mock repository. The placeholder screen that used to
/// stand in for these (and for every other not-yet-built route) is
/// gone now that nothing references it — `flutter analyze`'s own
/// `unused_element` check confirmed zero remaining call sites once
/// Money, Stock, and Sell all got real screens.
///
/// Named routes (via `name:`) rather than only paths, throughout — so
/// every navigation call site in the app reads as
/// `context.goNamed('home')` rather than a raw path string repeated at
/// every call site, which is exactly the kind of string duplication
/// that drifts silently once a path changes in only one place.
Page<void> _fulusNoTransitionPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(
      key: state.pageKey,
      child: child,
    );

final appRouter = GoRouter(
  initialLocation: '/',
  observers: [CurrentScreenObserver()],
  redirect: (context, state) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final user = container.read(sessionProvider);
    if (user == null) return null;

    final location = state.matchedLocation;
    if (location.startsWith('/more/settings/cloud')) {
      return user.role == AuthRole.owner ? null : '/';
    }
    if (user.role == AuthRole.owner) return null;
    final requiredPermissions = location.startsWith('/money')
        ? {Permission.viewMoney}
        : location.startsWith('/stock')
            ? _permissionsForStockRoute(location)
            : location.startsWith('/more')
                ? _permissionsForMoreRoute(location)
                : const <Permission>{};
    if (requiredPermissions.isEmpty) return null;

    // Reuse the app-scoped permission provider instead of performing a
    // fresh repository lookup on every navigation. The shell and its
    // protected screens already warm this provider, so normal taps resolve
    // from the cached permission set rather than introducing a second async
    // hop in the navigation path. The provider still comes from the same
    // repository and remains the enforcement source for direct/deep links.
    final permissions = await container.read(sessionPermissionsProvider.future);
    if (requiredPermissions.any(permissions.contains)) return null;
    return '/';
  },
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      pageBuilder: (context, state) =>
          _fulusNoTransitionPage(state, const EmployeeLoginScreen()),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _ShellGate(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              // HomeScreen takes the signed-in user's id/role as
              // constructor params rather than reading a session
              // provider itself (its own doc comment explains why —
              // testability in isolation) — the shell above already
              // guarantees a signed-in user by the time this builds,
              // but this Consumer stays as the one line that resolves
              // the actual id/role/permission HomeScreen needs, and as
              // a defensive fallback if that guarantee is ever
              // violated. canViewDashboardStats resolves the same
              // sessionPermissionsProvider _ShellGate and the redirect
              // above both read from — .value defaults to false for
              // the same fail-closed reason _ShellGate's own read of
              // it does (Riverpod 3.x: AsyncValue.value is now the
              // safe non-throwing accessor — .valueOrNull was renamed
              // to .value, not kept as a separate getter).
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(sessionProvider);
                    if (user == null) {
                      return const AuthGateScreen();
                    }
                    final permissions = ref.watch(sessionPermissionsProvider).value ?? const {};
                    final isOwner = user.role == AuthRole.owner;
                    return HomeScreen(
                      currentAuthUserId: user.id,
                      isOwner: isOwner,
                      canViewDashboardStats: permissions.contains(Permission.viewDashboardStats),
                      canViewMoney: permissions.contains(Permission.viewMoney),
                      canViewReports: permissions.contains(Permission.viewReports),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock',
              name: 'stock',
              pageBuilder: (context, state) => _fulusNoTransitionPage(state, StockScreen()),
              routes: [
                GoRoute(
                  path: 'product/:productId',
                  name: 'stockProductDetail',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, ProductDetailScreen(productId: state.pathParameters['productId']!)),
                ),
                GoRoute(
                  path: 'add',
                  name: 'stockAddProduct',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const AddEditProductScreen()),
                ),
                GoRoute(
                  path: 'edit',
                  name: 'stockEditProduct',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, AddEditProductScreen(existingProduct: state.extra as Product?)),
                ),
                GoRoute(
                  path: 'record',
                  name: 'stockRecordMovement',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, RecordStockMovementScreen(preselectedProduct: state.extra as Product?)),
                ),
                GoRoute(
                  path: 'history',
                  name: 'stockHistory',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, StockMovementHistoryScreen(productId: state.extra as String?)),
                ),
                GoRoute(
                  path: 'categories',
                  name: 'stockCategories',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const CategoriesScreen()),
                ),
                GoRoute(
                  path: 'bulk-import',
                  name: 'stockBulkImport',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const BulkImportScreen()),
                  routes: [
                    GoRoute(
                      path: 'review',
                      name: 'stockBulkImportReview',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, BulkImportReviewScreen(csvContent: state.extra as String)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/sell',
              name: 'sell',
              pageBuilder: (context, state) => _fulusNoTransitionPage(state, SellScreen()),
              routes: [
                GoRoute(
                  path: 'refund',
                  name: 'sellRefundSearch',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const RefundSearchScreen()),
                  routes: [
                    GoRoute(
                      path: ':saleId',
                      name: 'sellRefundConfirm',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, RefundConfirmScreen(saleId: state.pathParameters['saleId']!)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/money',
              name: 'money',
              pageBuilder: (context, state) => _fulusNoTransitionPage(state, MoneyScreen()),
              routes: [
                GoRoute(
                  path: 'history',
                  name: 'moneyHistory',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const MoneyHistoryScreen()),
                ),
                GoRoute(
                  path: 'transaction/:id',
                  name: 'moneyTransactionDetail',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, TransactionDetailScreen(
                    transactionId: state.pathParameters['id']!,
                    preloaded: state.extra is MoneyTransaction ? state.extra as MoneyTransaction : null,
                  )),
                ),
                GoRoute(
                  path: 'add-income',
                  name: 'moneyAddIncome',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const AddIncomeScreen()),
                ),
                GoRoute(
                  path: 'add-expense',
                  name: 'moneyAddExpense',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const AddExpenseScreen()),
                ),
                GoRoute(
                  path: 'customers',
                  name: 'moneyCustomers',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const CustomersListScreen()),
                  routes: [
                    GoRoute(
                      path: 'archived',
                      name: 'moneyArchivedCustomers',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, const ArchivedCustomersScreen()),
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'moneyCustomerProfile',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, CustomerProfileScreen(
                        customerId: state.pathParameters['id']!,
                        preloaded: state.extra is Customer ? state.extra as Customer : null,
                      )),
                      routes: [
                        GoRoute(
                          path: 'repay',
                          name: 'moneyRecordRepayment',
                          pageBuilder: (context, state) => _fulusNoTransitionPage(state, (() {
                            final extra = state.extra;
                            if (extra is Customer) return RecordRepaymentScreen(customer: extra);
                            // Defensive fallback — this route is only ever
                            // reached from a profile screen that already
                            // holds the Customer object; a bare id with no
                            // `extra` (a malformed deep link) has nothing
                            // to build a payment form against.
                            return const _MissingContextScreen(
                              title: 'Record repayment',
                              message: "Open the customer's profile first.",
                            );
                          })()),
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'receipts',
                  name: 'receiptHistory',
                  // Feature (Receipt History): a dedicated, sales-only
                  // browse-and-reprint screen — see that screen's own
                  // doc comment for why it's a separate route from
                  // `moneyHistory` rather than that screen with a type
                  // filter pre-selected.
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const ReceiptHistoryScreen()),
                ),
                GoRoute(
                  path: 'suppliers',
                  name: 'moneySuppliers',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const SuppliersListScreen()),
                  routes: [
                    GoRoute(
                      path: ':id',
                      name: 'moneySupplierProfile',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, SupplierProfileScreen(
                        supplierId: state.pathParameters['id']!,
                        preloaded: state.extra is Supplier ? state.extra as Supplier : null,
                      )),
                      routes: [
                        GoRoute(
                          path: 'pay',
                          name: 'moneyPaySupplier',
                          pageBuilder: (context, state) => _fulusNoTransitionPage(state, (() {
                            final extra = state.extra;
                            if (extra is Supplier) return PaySupplierScreen(supplier: extra);
                            return const _MissingContextScreen(
                              title: 'Pay supplier',
                              message: "Open the supplier's profile first.",
                            );
                          })()),
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'daily-closing',
                  name: 'moneyDailyClosingCount',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const DailyClosingCountScreen()),
                ),
                GoRoute(
                  path: 'daily-closing/summary',
                  name: 'moneyDailyClosingSummary',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, (() {
                    final extra = state.extra;
                    if (extra is DailyClosingSummary) return DailyClosingSummaryScreen(summary: extra);
                    // Only reachable with a summary in hand — closing the
                    // drawer produces the summary and pushes here in the
                    // same step, there's no separate persisted store of
                    // past closings to fetch one by id from.
                    return const _MissingContextScreen(
                      title: 'Day closed',
                      message: 'Close the day from the Money tab first.',
                    );
                  })()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              name: 'more',
              pageBuilder: (context, state) => _fulusNoTransitionPage(state, _MoreScreen()),
              routes: [
                GoRoute(
                  path: 'employees',
                  name: 'moreEmployees',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const EmployeesListScreen()),
                  routes: [
                    GoRoute(
                      path: 'deactivated',
                      name: 'moreEmployeesDeactivated',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, const DeactivatedEmployeesScreen()),
                    ),
                    GoRoute(
                      path: ':employeeId',
                      name: 'moreEmployeeDetail',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, EmployeeDetailScreen(employeeId: state.pathParameters['employeeId']!)),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'reports',
                  name: 'moreReports',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const ReportsScreen()),
                  routes: [
                    GoRoute(
                      path: 'sales',
                      name: 'moreReportsSalesTransactions',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, SalesTransactionsScreen(period: state.extra! as ReportPeriod)),
                    ),
                    GoRoute(
                      path: 'void/:saleId',
                      name: 'moreReportsVoidSale',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, VoidSaleScreen(saleId: state.pathParameters['saleId']!)),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'settings/backup',
                  name: 'moreSettingsBackup',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const BackupScreen()),
                ),
                GoRoute(
                  path: 'customers',
                  name: 'moreCustomers',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(
                    state,
                    const CustomersListScreen(openedFromMore: true),
                  ),
                  routes: [
                    GoRoute(
                      path: 'archived',
                      name: 'moreArchivedCustomers',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(
                        state,
                        const ArchivedCustomersScreen(openedFromMore: true),
                      ),
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'moreCustomerProfile',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(
                        state,
                        CustomerProfileScreen(
                          customerId: state.pathParameters['id']!,
                          preloaded: state.extra is Customer ? state.extra as Customer : null,
                          openedFromMore: true,
                        ),
                      ),
                      routes: [
                        GoRoute(
                          path: 'repay',
                          name: 'moreRecordRepayment',
                          pageBuilder: (context, state) => _fulusNoTransitionPage(state, (() {
                            final extra = state.extra;
                            if (extra is Customer) return RecordRepaymentScreen(customer: extra);
                            return const _MissingContextScreen(
                              title: 'Record repayment',
                              message: "Open the customer's profile first.",
                            );
                          })()),
                        ),
                        GoRoute(
                          path: 'transaction/:transactionId',
                          name: 'moreCustomerTransactionDetail',
                          pageBuilder: (context, state) => _fulusNoTransitionPage(
                            state,
                            TransactionDetailScreen(
                              transactionId: state.pathParameters['transactionId']!,
                              preloaded: state.extra is MoneyTransaction ? state.extra as MoneyTransaction : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'printers',
                  name: 'morePrinters',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(
                    state,
                    const PrinterPairingScreen(),
                  ),
                ),
                GoRoute(
                  path: 'settings/locations',
                  name: 'moreSettingsLocations',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const ManageLocationsScreen()),
                ),
                GoRoute(
                  path: 'settings',
                  name: 'moreSettings',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const SettingsMainScreen()),
                  routes: [
                    GoRoute(
                      path: 'cloud',
                      name: 'moreSettingsCloud',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, const FulusCloudConnectionScreen()),
                    ),
                    GoRoute(
                      path: 'printers',
                      name: 'moreSettingsPrinters',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, const PrinterPairingScreen()),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'sync',
                  name: 'moreSyncDetail',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const SyncDetailScreen()),
                ),
                GoRoute(
                  path: 'notifications',
                  name: 'moreNotifications',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const NotificationsScreen()),
                ),
                GoRoute(
                  path: 'diagnostics',
                  name: 'moreDiagnostics',
                  pageBuilder: (context, state) => _fulusNoTransitionPage(state, const DiagnosticsScreen()),
                  routes: [
                    GoRoute(
                      path: ':eventId',
                      name: 'moreDiagnosticDetail',
                      pageBuilder: (context, state) => _fulusNoTransitionPage(state, DiagnosticDetailScreen(eventId: state.pathParameters['eventId']!)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Which [Permission](s) unlock a `/more`-prefixed route — an empty
/// result means open to any signed-in user, a non-empty one means
/// "needs at least one of these" (almost always exactly one; see the
/// `/more/settings` case for why it's ever more than that). Order
/// matters: the more specific `settings/backup` check has to run
/// before the general `settings` prefix, since the general prefix
/// would otherwise match backup's path too.
///
/// `/more` itself and its Notifications/Diagnostics subroutes fall
/// through to the empty set deliberately — they're informational, not
/// business-sensitive, the same reasoning FulusAppShell's own doc
/// comment gives for why More stays visible to every role now.
Set<Permission> _permissionsForStockRoute(String location) {
  if (location.startsWith('/stock/add') ||
      location.startsWith('/stock/edit') ||
      location.startsWith('/stock/record') ||
      location.startsWith('/stock/categories') ||
      location.startsWith('/stock/bulk-import')) {
    return {Permission.manageStock};
  }
  // Viewing the catalog, product details, and stock history remains available
  // to signed-in employees; manageStock is the write/configuration boundary.
  return const <Permission>{};
}

Set<Permission> _permissionsForMoreRoute(String location) {
  if (location.startsWith('/more/customers')) return {Permission.viewMoney};
  if (location.startsWith('/more/printers')) return {Permission.manageSettings};
  if (location.startsWith('/more/employees')) return {Permission.manageEmployees};
  if (location.startsWith('/more/reports')) return {Permission.viewReports};
  if (location.startsWith('/more/settings/backup')) return {Permission.manageBackup};
  // Fulus Cloud is owner-only today; there is no permission that grants
  // cloud connection management to non-owners, so do not let a direct/deep
  // link bypass the owner-only UI gate below SettingsMainScreen.
  if (location.startsWith('/more/settings/cloud')) return {Permission.manageSettings};
  if (location == '/more/settings') {
    // The settings hub itself, not any of its subroutes — reachable
    // with either the general manageSettings grant or, on its own,
    // manageBackup: Backup lives as a row inside this hub screen (see
    // settings_main_screen.dart), and an owner may trust a Manager
    // with just backup/restore without handing them the rest of
    // Settings. That screen hides every other row for a
    // manageBackup-only visitor itself — this only has to get them
    // through the door.
    return {Permission.manageSettings, Permission.manageBackup};
  }
  if (location.startsWith('/more/settings')) return {Permission.manageSettings};
  if (location.startsWith('/more/sync')) return {Permission.manageSettings};
  return const {};
}

/// Resolves to exactly one of four things, in order: [AuthGateScreen]
/// (signed out), [OwnerSetupScreen] resumed at its business step
/// (signed in as an owner with no business configured — the
/// interrupted-setup recovery case), [FirstRunSetupScreen] (an owner
/// whose business WAS just configured but who hasn't seen the
/// nice-to-have first-run nudge yet), or [FulusAppShell] (the normal
/// case). See the `redirect` above and this router's own header comment
/// for the employee-enforcement half of this same gap-closure pass.
///
/// The business-configured check only runs for an owner session —
/// there's no path to an Employee account existing before a business
/// does (`createEmployeeAccount` is owner-initiated, and an owner
/// wouldn't reach Employees to provision one before their own business
/// setup finished), so checking for Employee sessions would just be an
/// unnecessary database read on every rebuild. [firstRunPromptSeenProvider]
/// (providers.dart) is watched directly rather than re-read from
/// [OnboardingState] here, for the same "a plain field mutating doesn't
/// trigger `ref.watch`" reason [sessionProvider] mirrors
/// `AuthRepository.currentUser` — see that provider's own doc comment.
class _ShellGate extends ConsumerStatefulWidget {
  const _ShellGate({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<_ShellGate> createState() => _ShellGateState();
}

class _ShellGateState extends ConsumerState<_ShellGate> {
  // Cached per-user rather than recreated on every rebuild (same reason
  // as AuthGateScreen's own _hasOwnerFuture) — but still recomputed if
  // the signed-in user actually changes, since a fresh sign-in is a
  // genuinely new question, not a stale one.
  AuthUser? _futureBuiltForUser;
  Future<bool>? _businessConfiguredFuture;

  /// Start location resolution as soon as the authenticated shell is
  /// entered. Stock, Sell, Home and several detail/report screens all depend
  /// on this same app-scoped value. Starting it here lets the first tab tap
  /// reuse the in-flight/cached result instead of briefly replacing the
  /// destination with a full-screen loading state.
  void _warmShellData() {
    ref.read(activeLocationIdProvider);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) {
      return const AuthGateScreen();
    }
    if (user.role != AuthRole.owner) {
      _warmShellData();
      // Owner's `showMoneyTab: true` below needs no lookup at all (see
      // FulusAppShell's own doc comment on the owner exemption); a
      // non-owner session does, via the same sessionPermissionsProvider
      // the redirect above and _MoreScreen below both read from.
      // .value defaults to false while the very first lookup for a
      // freshly-switched-in session is still resolving, which is the
      // fail-closed direction to default to for a nav button that would
      // otherwise flash visible then disappear once the real answer
      // arrives. (Riverpod 3.x renamed AsyncValue.valueOrNull to
      // .value — see the ShellGate's own note above.)
      final permissions = ref.watch(sessionPermissionsProvider).value ?? const {};
      return FulusAppShell(
        navigationShell: widget.navigationShell,
        showMoneyTab: permissions.contains(Permission.viewMoney),
      );
    }

    if (!identical(_futureBuiltForUser, user)) {
      _futureBuiltForUser = user;
      _businessConfiguredFuture = ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
    }

    return FutureBuilder<bool>(
      future: _businessConfiguredFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Business configuration is a security/routing invariant, not
          // optional hydration. Never expose the business shell while this
          // local check is unresolved: an interrupted owner setup must
          // resume OwnerSetupScreen before any business route is built.
          return const FulusScreen(body: FulusLoadingIndicator());
        }
        // Resolved through resolvePostSignInStage
        // (core/onboarding/onboarding_routing.dart) rather than the two
        // inline ifs this used to be — same behavior, now unit-testable
        // without a widget pump. See that function's own doc comment.
        final stage = resolvePostSignInStage(
          businessConfigured: snapshot.data!,
          firstRunPromptSeen: ref.watch(firstRunPromptSeenProvider),
          walkthroughStep: ref.watch(walkthroughStepProvider),
        );
        switch (stage) {
          case PostSignInStage.resumeBusinessSetup:
            return OwnerSetupScreen(startAtBusinessStep: true, resumingOwner: user);
          case PostSignInStage.showEssentialSettings:
            return const EssentialSettingsScreen();
          case PostSignInStage.showAddFirstProduct:
            return const AddFirstProductScreen();
          case PostSignInStage.showNavigationIntro:
            return const NavigationIntroScreen();
          case PostSignInStage.showFirstSaleIntro:
            final introSeen = ref.watch(firstSaleIntroSeenProvider);
            if (introSeen) {
              _warmShellData();
              return FulusAppShell(navigationShell: widget.navigationShell, showMoneyTab: true);
            }
            return const FirstSaleIntroScreen();
          case PostSignInStage.showFirstRunPrompt:
            return const FirstRunSetupScreen();
          case PostSignInStage.enterShell:
            _warmShellData();
            return FulusAppShell(navigationShell: widget.navigationShell, showMoneyTab: true);
        }
      },
    );
  }
}

/// **Foundation phase 2**: rebuilt on [FulusScreen]/[FulusListRow] —
/// same three real sub-screens as before, now using the shared
/// components instead of a bare [ListView] of [ListTile]s, as a
/// concrete example of the pattern for whoever builds the rest of
/// Settings.
///
/// Gap fix: the rest of Settings this class's own comment used to flag
/// as undone — Business info, Printers, Sync, Security — now exists at
/// SettingsMainScreen; the on-screen "Not yet built" text below is
/// replaced with a real link to it.
class _MoreScreen extends ConsumerWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final isOwner = user?.role == AuthRole.owner;
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const {};
    final canCustomers = isOwner || permissions.contains(Permission.viewMoney);
    final canEmployees = isOwner || permissions.contains(Permission.manageEmployees);
    final canReports = isOwner || permissions.contains(Permission.viewReports);
    final canSettings = isOwner ||
        permissions.contains(Permission.manageSettings) ||
        permissions.contains(Permission.manageBackup);
    final canManageSettings = isOwner || permissions.contains(Permission.manageSettings);

    Widget tileGrid(List<Widget> tiles) {
      // Flat, edge-to-edge icon-over-label grid. Cells touch with only
      // hairline dividers between them; there are no section cards or gaps.
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final cellHeight = textScale > 1.3 ? 144.0 : 132.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 640 ? 3 : 2;
          final rows = <Widget>[
            for (var i = 0; i < tiles.length; i += columns)
              SizedBox(
                height: cellHeight,
                child: Row(
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        child: i + c < tiles.length
                            ? tiles[i + c]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ];
          return Column(children: rows);
        },
      );
    }

    return FulusScreen(
      title: 'More',
      applyPadding: false,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          tileGrid([
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.customers,
              art: FulusArt.customers,
              iconColor: AppColors.customers,
              label: 'Customers',
              onTap: canCustomers ? () => context.pushNamed('moreCustomers') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.staff,
              art: FulusArt.staff,
              iconColor: AppColors.primary,
              label: 'Employees',
              onTap: canEmployees ? () => context.goNamed('moreEmployees') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.locations,
              art: FulusArt.locations,
              iconColor: AppColors.info,
              label: 'Locations',
              onTap: canManageSettings ? () => context.goNamed('moreSettingsLocations') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.settings,
              art: FulusArt.settings,
              iconColor: AppColors.primary,
              label: 'Settings',
              onTap: canSettings ? () => context.goNamed('moreSettings') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.reports,
              art: FulusArt.reports,
              iconColor: AppColors.reports,
              label: 'Reports',
              onTap: canReports ? () => context.goNamed('moreReports') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.notifications,
              art: FulusArt.notifications,
              iconColor: AppColors.warning,
              label: 'Alerts',
              onTap: () => context.goNamed('moreNotifications'),
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.backup,
              art: FulusArt.backup,
              iconColor: AppColors.success,
              label: 'Backup',
              onTap: canSettings ? () => context.goNamed('moreSettingsBackup') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.sync,
              art: FulusArt.sync,
              iconColor: AppColors.info,
              label: 'Sync',
              onTap: canManageSettings ? () => context.goNamed('moreSyncDetail') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.print,
              art: FulusArt.print,
              iconColor: AppColors.primary,
              label: 'Printers',
              onTap: canManageSettings ? () => context.pushNamed('morePrinters') : null,
            ),
            FulusFlatGridCell(
              iconSize: 56,
              icon: FulusIcons.bugReport,
              iconColor: AppColors.error,
              label: 'Diagnostics',
              onTap: () => context.goNamed('moreDiagnostics'),
            ),
          ]),
        ],
      ),
    );

}

/// A defensive fallback for the handful of Money routes that need an
/// object passed via `extra` (a `Customer`, `Supplier`, or
/// `DailyClosingSummary`) and were reached without one — normal
/// navigation from within the app always provides it; this only
/// matters for a malformed or stale deep link.
class _MissingContextScreen extends StatelessWidget {
  const _MissingContextScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: title,
      body: FulusEmptyState(icon: Icons.error_outline, headline: "Couldn't open this.", body: message),
    );
  }
}


