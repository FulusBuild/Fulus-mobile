# Changed/new files — Roles & Permissions, Backup & Restore, Tablet support

Paths below are relative to the repo root — drop this tree directly on
top of the existing project. 7 new files, 25 modified. Nothing else in
the repo was touched.

## New files

- `lib/domain/entities/permission.dart` — the `Permission` enum and
  per-role default bundles.
- `lib/data/local/database/tables/permission_tables.dart` — the
  `UserPermissions` table (schemaVersion 10).
- `lib/domain/repositories/permission_repository.dart` +
  `lib/data/repositories/permission_repository_impl.dart` — grant
  storage and the owner-exempt `hasPermission` check.
- `lib/features/more/employees/presentation/widgets/permission_editor.dart`
  — the checkbox-list editor and role-preset selector.
- `lib/features/auth/presentation/screens/backup_restore_decision_screen.dart`
  — the "Restore or start fresh" onboarding screen.
- `lib/core/theme/device_form_factor.dart` — the shared tablet/phone
  breakpoint (`kTabletBreakpoint`, `isTabletWidth`).

## Modified files

**Roles & Permissions**
- `lib/domain/entities/auth_user.dart` — `AuthRole` gains
  `manager`/`cashier`.
- `lib/data/local/database/database.dart` — table registered,
  schemaVersion 9→10, migration.
- `lib/domain/repositories/auth_repository.dart` +
  `lib/data/repositories/auth_repository_impl.dart` —
  `createEmployeeAccount` takes a `role`, seeds permissions.
- `lib/app/providers.dart` + `lib/app/bootstrap.dart` — new provider
  wired and overridden.
- `lib/app/router.dart` — permission-aware redirect (async), `/more`
  row visibility.
- `lib/app/app_shell.dart` — `isOwner` → `showMoneyTab`; More is
  unconditionally visible now.
- `lib/features/home/presentation/screens/home_screen.dart` —
  `canViewDashboardStats`; role label fixed for Manager/Cashier.
- `lib/data/repositories/dashboard_repository_impl.dart` — fixed a real
  bug: voided sales were missing the `deletedAt` filter and inflating
  Home's hero totals.
- `lib/features/sell/presentation/screens/refund_confirm_screen.dart`,
  `void_sale_screen.dart`,
  `lib/features/stock/presentation/screens/record_stock_movement_screen.dart`
  — approval-PIN trigger is now `approveWithoutSupervisor`, not
  `role == employee`.
- `lib/data/repositories/audit_repository_impl.dart` +
  `lib/domain/repositories/audit_repository.dart` — optional
  `hasAuditPermission` param, avoids a circular dependency.
- `lib/data/repositories/business_settings_repository_impl.dart` —
  `manageSettings` permission check.
- `lib/features/more/employees/presentation/screens/employee_detail_screen.dart`
  — role picker + live permission editor at login creation; "Access &
  permissions" editor for existing logins; a Manager can't grant a
  permission they don't hold themselves.
- `lib/features/more/settings/presentation/screens/settings_main_screen.dart`
  — rows hidden by permission (`manageSettings` vs `manageBackup`
  independently).

**Backup & Restore**
- `lib/core/onboarding/onboarding_routing.dart` — new
  `AuthGateStage.needsBackupDecision`.
- `lib/features/auth/presentation/screens/auth_gate_screen.dart` —
  detects an on-device backup and routes to the new decision screen.
- `lib/domain/usecases/backup_engine.dart` — new `imported` label.
- `lib/domain/repositories/backup_repository.dart` +
  `lib/data/repositories/backup_repository_impl.dart` —
  `importBackupFile()`, validates the SQLite header.
- `lib/features/more/settings/presentation/screens/backup_screen.dart`
  — "Restore from a file" via `file_picker`.

**Tablet support**
- `lib/main.dart` — references the shared breakpoint constant instead
  of a locally hardcoded `600`.
- `lib/app/app_shell.dart` — content centered and width-capped on
  tablet-width windows (same file as the Roles & Permissions change
  above).
