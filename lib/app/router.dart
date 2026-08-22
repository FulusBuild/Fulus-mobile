import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/onboarding/onboarding_routing.dart';
import '../core/theme/design_tokens.dart';
import '../domain/entities/app_notification.dart';
import '../domain/entities/auth_user.dart';
import '../domain/entities/customer.dart';
import '../domain/entities/product.dart';
import '../domain/entities/supplier.dart';
import '../features/auth/presentation/screens/auth_gate_screen.dart';
import '../features/auth/presentation/screens/owner_setup_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/money/domain/cash_drawer_state.dart';
import '../features/money/domain/money_transaction.dart';
import '../features/money/presentation/screens/add_expense_screen.dart';
import '../features/money/presentation/screens/add_income_screen.dart';
import '../features/money/presentation/screens/customer_profile_screen.dart';
import '../features/money/presentation/screens/customers_list_screen.dart';
import '../features/money/presentation/screens/daily_closing_count_screen.dart';
import '../features/money/presentation/screens/daily_closing_summary_screen.dart';
import '../features/money/presentation/screens/money_history_screen.dart';
import '../features/money/presentation/screens/money_screen.dart';
import '../features/money/presentation/screens/pay_supplier_screen.dart';
import '../features/money/presentation/screens/record_repayment_screen.dart';
import '../features/money/presentation/screens/supplier_profile_screen.dart';
import '../features/money/presentation/screens/suppliers_list_screen.dart';
import '../features/money/presentation/screens/transaction_detail_screen.dart';
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
///   [OwnerSetupScreen]'s two steps in an earlier session) used to land
///   straight in the shell with nothing configured. [_ShellGate] now
///   checks [BusinessSettingsRepository.hasBeenConfigured] for a
///   signed-in owner and resumes [OwnerSetupScreen] at its business
///   step instead, before ever building [FulusAppShell].
/// - Employee sessions previously reached `/money` and everything under
///   `/more` exactly like an owner would (Volume 9: "never sees Money,
///   Reports, Employees, or Settings"). [FulusAppShell] hides those nav
///   buttons for an Employee session, but a hidden button alone isn't
///   real enforcement (failure.dart's own `_Forbidden` doc comment makes
///   this same point about permission checks generally) — the
///   `redirect` below is what actually blocks reaching those routes,
///   the same way a direct call bypassing the UI has to be rejected too.
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
final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final user = ProviderScope.containerOf(context, listen: false).read(sessionProvider);
    if (user == null || user.role == AuthRole.owner) return null;
    // Employee session — Stock stays reachable (see app_shell.dart's
    // own doc comment on why that one is a deliberately conservative
    // reading, not a confirmed spec decision); Money and everything
    // under More do not.
    final blockedForEmployee =
        state.matchedLocation.startsWith('/money') || state.matchedLocation.startsWith('/more');
    return blockedForEmployee ? '/' : null;
  },
  routes: [
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
              // the actual id/role HomeScreen needs, and as a
              // defensive fallback if that guarantee is ever violated.
              builder: (context, state) => Consumer(
                builder: (context, ref, _) {
                  final user = ref.watch(sessionProvider);
                  if (user == null) {
                    return const AuthGateScreen();
                  }
                  return HomeScreen(
                    currentAuthUserId: user.id,
                    isOwner: user.role == AuthRole.owner,
                  );
                },
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock',
              name: 'stock',
              builder: (context, state) => const StockScreen(),
              routes: [
                GoRoute(
                  path: 'product/:productId',
                  name: 'stockProductDetail',
                  builder: (context, state) =>
                      ProductDetailScreen(productId: state.pathParameters['productId']!),
                ),
                GoRoute(
                  path: 'add',
                  name: 'stockAddProduct',
                  builder: (context, state) => const AddEditProductScreen(),
                ),
                GoRoute(
                  path: 'edit',
                  name: 'stockEditProduct',
                  builder: (context, state) => AddEditProductScreen(existingProduct: state.extra as Product?),
                ),
                GoRoute(
                  path: 'record',
                  name: 'stockRecordMovement',
                  builder: (context, state) =>
                      RecordStockMovementScreen(preselectedProduct: state.extra as Product?),
                ),
                GoRoute(
                  path: 'history',
                  name: 'stockHistory',
                  builder: (context, state) => StockMovementHistoryScreen(productId: state.extra as String?),
                ),
                GoRoute(
                  path: 'categories',
                  name: 'stockCategories',
                  builder: (context, state) => const CategoriesScreen(),
                ),
                GoRoute(
                  path: 'bulk-import',
                  name: 'stockBulkImport',
                  builder: (context, state) => const BulkImportScreen(),
                  routes: [
                    GoRoute(
                      path: 'review',
                      name: 'stockBulkImportReview',
                      builder: (context, state) => BulkImportReviewScreen(csvContent: state.extra as String),
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
              builder: (context, state) => const SellScreen(),
              routes: [
                GoRoute(
                  path: 'refund',
                  name: 'sellRefundSearch',
                  builder: (context, state) => const RefundSearchScreen(),
                  routes: [
                    GoRoute(
                      path: ':saleId',
                      name: 'sellRefundConfirm',
                      builder: (context, state) =>
                          RefundConfirmScreen(saleId: state.pathParameters['saleId']!),
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
              builder: (context, state) => const MoneyScreen(),
              routes: [
                GoRoute(
                  path: 'history',
                  name: 'moneyHistory',
                  builder: (context, state) => const MoneyHistoryScreen(),
                ),
                GoRoute(
                  path: 'transaction/:id',
                  name: 'moneyTransactionDetail',
                  builder: (context, state) => TransactionDetailScreen(
                    transactionId: state.pathParameters['id']!,
                    preloaded: state.extra is MoneyTransaction ? state.extra as MoneyTransaction : null,
                  ),
                ),
                GoRoute(
                  path: 'add-income',
                  name: 'moneyAddIncome',
                  builder: (context, state) => const AddIncomeScreen(),
                ),
                GoRoute(
                  path: 'add-expense',
                  name: 'moneyAddExpense',
                  builder: (context, state) => const AddExpenseScreen(),
                ),
                GoRoute(
                  path: 'customers',
                  name: 'moneyCustomers',
                  builder: (context, state) => const CustomersListScreen(),
                  routes: [
                    GoRoute(
                      path: ':id',
                      name: 'moneyCustomerProfile',
                      builder: (context, state) => CustomerProfileScreen(
                        customerId: state.pathParameters['id']!,
                        preloaded: state.extra is Customer ? state.extra as Customer : null,
                      ),
                      routes: [
                        GoRoute(
                          path: 'repay',
                          name: 'moneyRecordRepayment',
                          builder: (context, state) {
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
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'suppliers',
                  name: 'moneySuppliers',
                  builder: (context, state) => const SuppliersListScreen(),
                  routes: [
                    GoRoute(
                      path: ':id',
                      name: 'moneySupplierProfile',
                      builder: (context, state) => SupplierProfileScreen(
                        supplierId: state.pathParameters['id']!,
                        preloaded: state.extra is Supplier ? state.extra as Supplier : null,
                      ),
                      routes: [
                        GoRoute(
                          path: 'pay',
                          name: 'moneyPaySupplier',
                          builder: (context, state) {
                            final extra = state.extra;
                            if (extra is Supplier) return PaySupplierScreen(supplier: extra);
                            return const _MissingContextScreen(
                              title: 'Pay supplier',
                              message: "Open the supplier's profile first.",
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'daily-closing',
                  name: 'moneyDailyClosingCount',
                  builder: (context, state) => const DailyClosingCountScreen(),
                ),
                GoRoute(
                  path: 'daily-closing/summary',
                  name: 'moneyDailyClosingSummary',
                  builder: (context, state) {
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
                  },
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
              builder: (context, state) => const _MoreScreen(),
              routes: [
                GoRoute(
                  path: 'employees',
                  name: 'moreEmployees',
                  builder: (context, state) => const EmployeesListScreen(),
                  routes: [
                    GoRoute(
                      path: ':employeeId',
                      name: 'moreEmployeeDetail',
                      builder: (context, state) =>
                          EmployeeDetailScreen(employeeId: state.pathParameters['employeeId']!),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'reports',
                  name: 'moreReports',
                  builder: (context, state) => const ReportsScreen(),
                  routes: [
                    GoRoute(
                      path: 'sales',
                      name: 'moreReportsSalesTransactions',
                      builder: (context, state) =>
                          SalesTransactionsScreen(period: state.extra! as ReportPeriod),
                    ),
                    GoRoute(
                      path: 'void/:saleId',
                      name: 'moreReportsVoidSale',
                      builder: (context, state) =>
                          VoidSaleScreen(saleId: state.pathParameters['saleId']!),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'settings/backup',
                  name: 'moreSettingsBackup',
                  builder: (context, state) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'settings/locations',
                  name: 'moreSettingsLocations',
                  builder: (context, state) => const ManageLocationsScreen(),
                ),
                GoRoute(
                  path: 'settings',
                  name: 'moreSettings',
                  builder: (context, state) => const SettingsMainScreen(),
                  routes: [
                    GoRoute(
                      path: 'printers',
                      name: 'moreSettingsPrinters',
                      builder: (context, state) => const PrinterPairingScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'sync',
                  name: 'moreSyncDetail',
                  builder: (context, state) => const SyncDetailScreen(),
                ),
                GoRoute(
                  path: 'notifications',
                  name: 'moreNotifications',
                  builder: (context, state) => const NotificationsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) {
      return const AuthGateScreen();
    }
    if (user.role != AuthRole.owner) {
      return FulusAppShell(navigationShell: widget.navigationShell, isOwner: false);
    }

    if (!identical(_futureBuiltForUser, user)) {
      _futureBuiltForUser = user;
      _businessConfiguredFuture = ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
    }

    return FutureBuilder<bool>(
      future: _businessConfiguredFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
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
            return introSeen
                ? FulusAppShell(navigationShell: widget.navigationShell, isOwner: true)
                : const FirstSaleIntroScreen();
          case PostSignInStage.showFirstRunPrompt:
            return const FirstRunSetupScreen();
          case PostSignInStage.enterShell:
            return FulusAppShell(navigationShell: widget.navigationShell, isOwner: true);
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
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'More',
      applyPadding: false,
      body: ListView(
        children: [
          FulusListRow(
            title: const Text('Employees'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreEmployees'),
          ),
          const FulusListDivider(indented: false),
          FulusListRow(
            title: const Text('Reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreReports'),
          ),
          const FulusListDivider(indented: false),
          FulusListRow(
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('moreSettings'),
          ),
          const FulusListDivider(indented: false),
          Consumer(
            builder: (context, ref, _) {
              final notificationsAsync = ref.watch(_moreNotificationsProvider);
              final unread = notificationsAsync.valueOrNull?.where((n) => !n.isRead).length ?? 0;
              return FulusListRow(
                title: const Text('Notifications'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unread > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warningOf(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.goNamed('moreNotifications'),
              );
            },
          ),
        ],
      ),
    );
  }
}

final _moreNotificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationRepositoryProvider).watchAll();
});

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


