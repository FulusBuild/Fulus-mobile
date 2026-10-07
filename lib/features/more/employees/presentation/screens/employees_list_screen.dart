import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/errors/module_failures.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/async_timeout.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../domain/entities/permission.dart';
import '../../../../../shared/widgets/widgets.dart';

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});
  @override
  ConsumerState<EmployeesListScreen> createState() => _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  Stream<List<Employee>> get _employeesStream => ref.read(employeeRepositoryProvider).watchEmployees(isActive: true);

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Employees',

      actions: [
        FulusIconButton(
          icon: FulusIcons.add,
          tooltip: 'Add team member',
          onPressed: () => _openEmployeeSheet(context),
        ),
        FulusIconButton(
          icon: FulusIcons.staff,
          tooltip: 'Deactivated team members',
          onPressed: () => context.pushNamed('moreEmployeesDeactivated'),
        ),
      ],
      floatingActionButton: null,
      body: StreamBuilder<List<Employee>>(
        stream: _employeesStream.withFulusLoadingTimeout(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load your team.",
              reassurance: 'No team data was changed — this is only a loading problem.',
              onRetry: () => setState(() {}),
            );
          }
          final employees = snapshot.data ?? const <Employee>[];
          if (!snapshot.hasData) return const _EmployeesLoadingSkeleton();
          if (employees.isEmpty) {
            return FulusEmptyState(
              icon: FulusIcons.staff,
              headline: 'No team members yet',
              body: 'Add your first team member to manage attendance and access.',
              actionLabel: 'Add team member',
              onAction: () => _openEmployeeSheet(context),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, 120),
                children: [
                  _TeamOverview(employees: employees),
                  const SizedBox(height: AppSpacing.lg),
                  FulusSectionHeader(
                    title: 'Active team',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < employees.length; i++) ...[
                          _EmployeeTile(
                            employee: employees[i],
                            onEdit: () => _openEmployeeSheet(context, existing: employees[i]),
                          ),
                          if (i < employees.length - 1) const FulusListDivider(),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEmployeeSheet(BuildContext context, {Employee? existing}) async {
    final invitation = await showFulusBottomSheet<String>(
      context: context,
      title: existing == null ? 'Add team member' : 'Edit team member',
      builder: (_) => _EmployeeFormSheet(existing: existing),
    );
    if (invitation == null || !context.mounted) return;

    await SharePlus.instance.share(
      ShareParams(
        text: invitation,
        title: 'Invite to Fulus',
        subject: 'Fulus team invitation',
      ),
    );
  }
}

class _TeamOverview extends StatelessWidget {
  const _TeamOverview({required this.employees});
  final List<Employee> employees;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      child: SizedBox(
        height: 128,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                FulusIcons.staff,
                color: AppColors.primary,
                size: AppIconSize.emphasis,
              ),
              const Spacer(),
              Text(
                employees.length.toString() +
                    ' active ' +
                    (employees.length == 1 ? 'employee' : 'employees'),
                style: AppTypography.heading.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.existing});
  final Employee? existing;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _emailController = TextEditingController(text: widget.existing?.email ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late String _role = _initialRole(widget.existing?.role);
  bool _saving = false;

  String _initialRole(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'manager' || normalized == 'admin') return 'Manager';
    if (normalized == 'employee') return 'Employee';
    return 'Cashier';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    if (name.length < 2) {
      showFulusSnackbar(context, message: 'Enter the team member’s name.');
      return;
    }
    if (widget.existing == null && (email.isEmpty || !email.contains('@'))) {
      showFulusSnackbar(context, message: 'Add the email they will use for Fulus.');
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final businessId = existing == null
          ? ref.read(fulusConnectionStateProvider).selectedBusinessId
          : null;
      if (existing == null && businessId == null) {
        throw StateError('This business is not ready for employee invitations yet.');
      }

      final draft = EmployeeDraft(
        fullName: name,
        role: _role,
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        email: existing?.email ?? email,
        authUserId: existing?.authUserId,
        department: existing?.department,
        position: existing?.position,
        salary: existing?.salary,
        dateHired: existing?.dateHired,
        locationId: existing?.locationId,
      );
      final repo = ref.read(employeeRepositoryProvider);
      final saved = existing == null
          ? await repo.createEmployee(draft)
          : await repo.updateEmployee(existing.id, draft);

      if (existing != null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final localLocationId = saved.locationId;
      final localLocation = localLocationId == null
          ? null
          : await ref.read(locationRepositoryProvider).getLocationById(localLocationId);
      final cloudLocationId = localLocation?.serverId;
      if (localLocationId != null && (cloudLocationId == null || cloudLocationId.isEmpty)) {
        throw StateError('This location is still being backed up. Try again in a moment.');
      }

      final invite = await ref.read(fulusConnectionStateProvider).createStaffInvite(
            roleName: _cloudRole(saved.role),
            email: saved.email!,
            invitedName: saved.fullName,
            permissionCodes: _cloudPermissionCodesForRole(saved.role),
            locationId: cloudLocationId,
            employeeClientReference: saved.id,
            employee: {
              'full_name': saved.fullName,
              'role': saved.role,
              'phone': saved.phone,
              'email': saved.email,
              'department': saved.department,
              'position': saved.position,
              'salary': saved.salary,
              'date_hired': saved.dateHired?.toIso8601String(),
              'location_id': cloudLocationId,
            },
          );

      if (!mounted) return;
      Navigator.of(context).pop(
        'You’ve been invited to use Fulus for ${saved.fullName}.\n\n'
        'Email: ${saved.email}\n'
        'Role: ${saved.role ?? 'Employee'}\n\n'
        'Open Fulus, tap “Join as employee”, and enter this invitation code:\n'
        '${invite.token}\n\n'
        'The invitation expires in 24 hours.',
      );
    } on EmployeeValidationException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: e.message);
      }
    } on Failure catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: "Couldn't finish adding this team member. Try again.");
      }
    }
  }

  String _cloudRole(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'manager':
      case 'admin':
        return 'manager';
      case 'cashier':
        return 'cashier';
      default:
        return 'employee';
    }
  }

  // Invite permissions mirror the selected cloud role defaults so the
  // invitation is complete at creation time rather than relying on a later
  // repair step.
  List<String> _cloudPermissionCodesForRole(String? role) {
    final authRole = switch (_cloudRole(role)) {
      'manager' => AuthRole.manager,
      'cashier' => AuthRole.cashier,
      _ => AuthRole.employee,
    };
    return _cloudPermissionCodes(Permission.defaultsForRole(authRole));
  }

  List<String> _cloudPermissionCodes(Set<Permission> permissions) {
    final codes = <String>{};
    for (final permission in permissions) {
      switch (permission) {
        case Permission.viewMoney:
          codes.addAll({'cash.read', 'finance.read', 'sales.read', 'customers.read'});
        case Permission.viewDashboardStats:
          codes.add('business.read');
        case Permission.approveWithoutSupervisor:
          codes.addAll({'returns.approve', 'sales.void'});
        case Permission.manageStock:
          codes.addAll({'catalog.manage', 'inventory.adjust', 'inventory.transfer'});
        case Permission.viewReports:
          codes.add('reports.read');
        case Permission.manageEmployees:
          codes.add('employees.manage');
        case Permission.manageSettings:
          codes.addAll({'business.manage', 'locations.manage'});
        case Permission.manageBackup:
          codes.add('backup.manage');
        case Permission.viewAuditLog:
          codes.add('audit.read');
      }
    }
    return codes.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Add their name, email and role once. Fulus will create the invitation for you.',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ),
            FulusTextField(label: 'Full name', controller: _nameController, enabled: !_saving),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(
              label: 'Email',
              controller: _emailController,
              enabled: !_saving && isNew,
              keyboardType: TextInputType.emailAddress,
              helperText: isNew
                  ? 'This becomes their Fulus login email.'
                  : 'Login email cannot be changed here.',
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Role', style: AppTypography.subheading),
            const SizedBox(height: AppSpacing.xs),
            FulusChipRow(
              children: [
                for (final role in const ['Cashier', 'Manager', 'Employee'])
                  FulusChip(
                    label: role,
                    selected: _role == role,
                    onTap: () {
                      if (!_saving && isNew) setState(() => _role = role);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(
              label: 'Phone (optional)',
              controller: _phoneController,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: isNew ? 'Add & invite' : 'Save changes',
                loading: _saving,
                onPressed: _saving ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeTile extends ConsumerWidget {
  const _EmployeeTile({required this.employee, required this.onEdit});
  final Employee employee;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return FulusListRow(
          onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
          leading: FulusAvatar(name: employee.fullName),
          title: Text(employee.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(employee.role ?? 'Team member', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: compact
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FulusIconButton(
                      icon: FulusIcons.calendar,
                      tooltip: 'Mark attendance',
                      onPressed: () => _markToday(context, ref),
                    ),
                    FulusIconButton(
                      icon: FulusIcons.edit,
                      tooltip: 'Edit',
                      onPressed: onEdit,
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (employee.authUserId == null)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: Icon(
                          FulusIcons.person,
                          color: AppColors.warningOf(context),
                          size: AppIconSize.compact,
                        ),
                      ),
                    Text(
                      employee.phone ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FulusIconButton(
                      icon: FulusIcons.calendar,
                      tooltip: 'Mark attendance',
                      onPressed: () => _markToday(context, ref),
                    ),
                    FulusIconButton(
                      icon: FulusIcons.edit,
                      tooltip: 'Edit',
                      onPressed: onEdit,
                    ),
                    Icon(FulusIcons.chevronRight, color: AppColors.textSecondaryOf(context)),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _markToday(BuildContext context, WidgetRef ref) async {
    final status = await showFulusBottomSheet<AttendanceStatus>(
      context: context,
      title: 'Mark attendance',
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final status in AttendanceStatus.values)
            FulusListRow(
              onTap: () => Navigator.of(context).pop(status),
              leading: Icon(FulusIcons.check, color: AppColors.primaryOf(context)),
              title: Text(status.name),
            ),
        ],
      ),
    );
    if (status == null) return;
    try {
      await ref.read(employeeRepositoryProvider).markAttendance(
            employeeId: employee.id,
            date: DateTime.now(),
            status: status,
          );
      if (context.mounted) {
        showFulusSnackbar(context, message: 'Attendance marked as ${status.name}.');
      }
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't mark attendance. Try again.");
      }
    }
  }
}
class _EmployeesLoadingSkeleton extends StatelessWidget {
  const _EmployeesLoadingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.sm),
    children: const [
      FulusCardSkeleton(),
      SizedBox(height: AppSpacing.sm),
      FulusListRowSkeleton(hasLeading: true),
      FulusListRowSkeleton(hasLeading: true),
      FulusListRowSkeleton(hasLeading: true),
      FulusListRowSkeleton(hasLeading: true),
    ],
  );
}
