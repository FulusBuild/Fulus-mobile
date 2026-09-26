import 'package:flutter/material.dart';

import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/permission.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Display name + one-line description for each [Permission] — kept
/// here in the presentation layer rather than on the enum itself, same
/// separation home_screen.dart's own `_roleLabel` helper keeps for
/// [AuthRole]: the domain layer names *what* a capability is, not how
/// it reads in a checkbox list.
String permissionLabel(Permission permission) {
  switch (permission) {
    case Permission.viewMoney:
      return 'View Money';
    case Permission.viewDashboardStats:
      return 'View dashboard stats';
    case Permission.approveWithoutSupervisor:
      return 'Approve refunds & voids';
    case Permission.manageStock:
      return 'Manage stock';
    case Permission.viewReports:
      return 'View reports';
    case Permission.manageEmployees:
      return 'Manage team & access';
    case Permission.manageSettings:
      return 'Manage settings';
    case Permission.manageBackup:
      return 'Backup & restore';
    case Permission.viewAuditLog:
      return 'View audit log';
  }
}

String permissionDescription(Permission permission) {
  switch (permission) {
    case Permission.viewMoney:
      return "See the Money tab and this business's transaction history.";
    case Permission.viewDashboardStats:
      return "See Home's notices, quick actions, and activity feed — not just their own shift.";
    case Permission.approveWithoutSupervisor:
      return 'Issue a refund, void a sale, or record a stock-out/adjustment without a PIN from you.';
    case Permission.manageStock:
      return 'Record stock-in, adjustments, and transfers, not just sale-driven stock-out.';
    case Permission.viewReports:
      return 'See the Reports section under More.';
    case Permission.manageEmployees:
      return "Add, edit, and set other team members' access — including their own permissions.";
    case Permission.manageSettings:
      return 'Business settings, printers, locations, and sync.';
    case Permission.manageBackup:
      return 'Create, restore, and manage backups from Settings.';
    case Permission.viewAuditLog:
      return "View this business's audit log.";
  }
}

/// A checkbox per [Permission], each tile carrying its own one-line
/// description — used both for the initial grant while setting up a
/// login (_SetUpLoginSheet, seeded from a role preset the owner can
/// adjust before creating) and for editing an existing login's grant
/// afterward (EmployeeDetailScreen's own "Access & permissions"
/// section). Stateless by design: the caller owns [selected] and gets
/// every change back through [onChanged] rather than this widget
/// holding its own copy, the same "caller owns the state, this widget
/// is just its view" shape FulusTextField's controller-based API uses
/// elsewhere in this app.
///
/// [grantableBy] is the ACTING user's own held permissions (an Owner
/// passes [Permission.all]) — Permission.manageEmployees's own doc
/// comment is the rule this enforces: a Manager who themselves lack,
/// say, manageBackup can't hand it to someone else either, no matter
/// what they're editing. A row outside [grantableBy] renders disabled
/// (can't be toggled either direction) but still shows its true
/// current state — a Manager without manageBackup can still SEE
/// whether the person they're editing has it, just can't be the one
/// who changes that specific row.
class PermissionEditor extends StatelessWidget {
  const PermissionEditor({super.key, required this.selected, required this.onChanged, required this.grantableBy});

  final Set<Permission> selected;
  final ValueChanged<Set<Permission>> onChanged;
  final Set<Permission> grantableBy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final permission in Permission.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FulusActionTile(
              icon: FulusIcons.lock,
              label: permissionLabel(permission),
              subtitle: grantableBy.contains(permission)
                  ? permissionDescription(permission)
                  : '${permissionDescription(permission)} (you can\'t change this permission.)',
              onTap: grantableBy.contains(permission)
                  ? () {
                      final next = Set<Permission>.of(selected);
                      if (next.contains(permission)) {
                        next.remove(permission);
                      } else {
                        next.add(permission);
                      }
                      onChanged(next);
                    }
                  : null,
              trailing: Checkbox(
                value: selected.contains(permission),
                onChanged: grantableBy.contains(permission)
                    ? (checked) {
                        final next = Set<Permission>.of(selected);
                        if (checked ?? false) {
                          next.add(permission);
                        } else {
                          next.remove(permission);
                        }
                        onChanged(next);
                      }
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// A three-way [SegmentedButton] for the non-owner role presets —
/// deliberately excludes AuthRole.owner (see
/// AuthRepository.createEmployeeAccount's own doc comment: this is
/// never the path to a second owner).
class RolePresetSelector extends StatelessWidget {
  const RolePresetSelector({super.key, required this.selected, required this.onChanged});

  final AuthRolePreset selected;
  final ValueChanged<AuthRolePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return FulusChipRow(
      children: [
        FulusChip(
          label: 'Manager',
          selected: selected == AuthRolePreset.manager,
          onTap: () => onChanged(AuthRolePreset.manager),
        ),
        FulusChip(
          label: 'Cashier',
          selected: selected == AuthRolePreset.cashier,
          onTap: () => onChanged(AuthRolePreset.cashier),
        ),
        FulusChip(
          label: 'Employee',
          selected: selected == AuthRolePreset.employee,
          onTap: () => onChanged(AuthRolePreset.employee),
        ),
      ],
    );
  }
}

/// The three [AuthRole] values [RolePresetSelector] actually offers —
/// a distinct type from [AuthRole] itself so this widget's API can't
/// even be called with [AuthRole.owner] by mistake.
enum AuthRolePreset {
  manager,
  cashier,
  employee;

  AuthRole get role => switch (this) {
        AuthRolePreset.manager => AuthRole.manager,
        AuthRolePreset.cashier => AuthRole.cashier,
        AuthRolePreset.employee => AuthRole.employee,
      };
}
