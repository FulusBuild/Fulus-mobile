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
      subtitle: 'People who help run your business',
      actions: [
        FulusIconButton(
          icon: Icons.person_off_outlined,
          tooltip: 'Deactivated team members',
          onPressed: () => context.pushNamed('moreEmployeesDeactivated'),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add member'),
      ),
      body: StreamBuilder<List<Employee>>(
        stream: _employeesStream,
        builder: (context, snapshot) {
          final employees = snapshot.data ?? const <Employee>[];
          if (!snapshot.hasData) return const FulusLoadingIndicator();
          if (employees.isEmpty) {
            return FulusEmptyState(
              icon: Icons.people_outline,
              headline: 'No team members yet',
              body: 'Add your first team member to manage attendance and access.',
              actionLabel: 'Add team member',
              onAction: () => _openAddSheet(context),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, 120),
                children: [
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
                          _EmployeeTile(employee: employees[i]),
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

  Future<void> _openAddSheet(BuildContext context) => showFulusBottomSheet<void>(
        context: context,
        title: 'Add team member',
        builder: (_) => const _AddEmployeeSheet(),
      );
}

class _TeamOverview extends StatelessWidget {
  const _TeamOverview({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selectedTintOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.groups_outlined, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your team', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 2),
                Text(
                  '$count active ${count == 1 ? 'member' : 'members'}',
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Manage access and attendance from each profile.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEmployeeSheet extends ConsumerStatefulWidget {
  const _AddEmployeeSheet();
  @override
  ConsumerState<_AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends ConsumerState<_AddEmployeeSheet> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _phoneController = TextEditingController();
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
      await ref.read(employeeRepositoryProvider).createEmployee(
            EmployeeDraft(
              fullName: _nameController.text,
              role: _roleController.text.trim().isEmpty ? null : _roleController.text.trim(),
              phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } on EmployeeValidationException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: e.message);
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
                child: FulusButton(label: 'Add member', loading: _saving, onPressed: _saving ? null : _submit),
              ),
            ],
          ),
        ),
      );
}

class _EmployeeTile extends ConsumerWidget {
  const _EmployeeTile({required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FulusListRow(
        onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
        leading: FulusAvatar(name: employee.fullName),
        title: Text(employee.fullName),
        subtitle: Text(employee.role ?? (employee.phone ?? 'Team member')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (employee.authUserId == null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Icon(Icons.no_accounts_outlined, color: AppColors.warningOf(context), size: AppIconSize.compact),
              ),
            FulusIconButton(
              icon: Icons.event_available_outlined,
              tooltip: 'Mark attendance',
              onPressed: () => _markToday(context, ref),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
          ],
        ),
      );

  Future<void> _markToday(BuildContext context, WidgetRef ref) async {
    final status = await showFulusBottomSheet<AttendanceStatus>(
      context: context,
      title: 'Mark attendance',
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in AttendanceStatus.values)
            FulusListRow(
              onTap: () => Navigator.of(context).pop(s),
              leading: Icon(Icons.circle_outlined, color: AppColors.primaryOf(context)),
              title: Text(s.name),
            ),
        ],
      ),
    );
    if (status == null) return;
    await ref.read(employeeRepositoryProvider).markAttendance(employeeId: employee.id, date: DateTime.now(), status: status);
  }
}
