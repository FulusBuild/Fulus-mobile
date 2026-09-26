import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/module_failures.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});
  @override
  ConsumerState<EmployeesListScreen> createState() => _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  late final Stream<List<Employee>> _employeesStream = ref.read(employeeRepositoryProvider).watchEmployees(isActive: true);

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Team',
      subtitle: 'People, access and attendance',
      backgroundColor: const Color(0xFF061B3A),
      headerBackgroundColor: const Color(0xFF061B3A),
      actions: [
        FulusIconButton(
          icon: FulusIcons.staff,
          tooltip: 'Deactivated team members',
          onPressed: () => context.pushNamed('moreEmployeesDeactivated'),
        ),
      ],
      floatingActionButton: null,
      body: StreamBuilder<List<Employee>>(
        stream: _employeesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load your team.",
              reassurance: 'No team data was changed — this is only a loading problem.',
              onRetry: () => setState(() {}),
            );
          }
          final employees = snapshot.data ?? const <Employee>[];
          if (!snapshot.hasData) return const FulusLoadingIndicator();
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
                  FulusActionTile(
                    icon: FulusIcons.person,
                    label: 'Add team member',
                    subtitle: 'Add a person and manage their access',
                    onTap: () => _openEmployeeSheet(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _TeamOverview(count: employees.length),
                  const SizedBox(height: AppSpacing.lg),
                  FulusSectionHeader(
                    title: 'Active team',
                    subtitle: '${employees.length} ${employees.length == 1 ? 'member' : 'members'}',
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

  Future<void> _openEmployeeSheet(BuildContext context, {Employee? existing}) => showFulusBottomSheet<void>(
        context: context,
        title: existing == null ? 'Add team member' : 'Edit team member',
        builder: (_) => _EmployeeFormSheet(existing: existing),
      );
}

class _TeamOverview extends StatelessWidget {
  const _TeamOverview({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return FulusStatGrid(
      spacing: AppSpacing.sm,
      minTileWidth: 150,
      cards: [
        FulusStatCard(
          icon: FulusIcons.staff,
          label: 'Active team',
          value: '\$count \${count == 1 ? "member" : "members"}',
        ),
      ],
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
  late final _roleController = TextEditingController(text: widget.existing?.role ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final draft = EmployeeDraft(
        fullName: _nameController.text.trim(),
        role: _roleController.text.trim().isEmpty ? null : _roleController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        authUserId: existing?.authUserId,
        department: existing?.department,
        position: existing?.position,
        salary: existing?.salary,
        email: existing?.email,
        dateHired: existing?.dateHired,
        locationId: existing?.locationId,
      );
      final repo = ref.read(employeeRepositoryProvider);
      if (existing == null) {
        await repo.createEmployee(draft);
      } else {
        await repo.updateEmployee(existing.id, draft);
      }
      if (mounted) Navigator.of(context).pop();
    } on EmployeeValidationException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: "Couldn't save this team member. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FulusTextField(label: 'Full name', controller: _nameController),
              const SizedBox(height: AppSpacing.sm),
              FulusTextField(label: 'Role (e.g. Cashier)', controller: _roleController),
              const SizedBox(height: AppSpacing.sm),
              FulusTextField(label: 'Phone (optional)', controller: _phoneController, keyboardType: TextInputType.phone),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FulusButton(
                  label: widget.existing == null ? 'Add member' : 'Save changes',
                  loading: _saving,
                  onPressed: _saving ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      );
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
