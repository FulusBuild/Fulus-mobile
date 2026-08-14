import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/module_failures.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Volume 9's roster screen — list + add + per-employee attendance
/// marking. Leave request review, employee detail, and access
/// revocation now live on EmployeeDetailScreen (tap a row) — see that
/// screen's own header comment for why all three landed together.
class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() => _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  // Cached rather than called inline in build(): watchEmployees() opens a
  // new Drift query subscription each call, so calling it directly in
  // build() would resubscribe (and flash back through "waiting") on
  // every rebuild, not just when the roster actually needs re-fetching.
  late final Stream<List<Employee>> _employeesStream =
      ref.read(employeeRepositoryProvider).watchEmployees(isActive: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddSheet(context),
        child: const Icon(Icons.person_add),
      ),
      body: StreamBuilder<List<Employee>>(
        stream: _employeesStream,
        builder: (context, snapshot) {
          final employees = snapshot.data ?? const [];
          if (!snapshot.hasData) {
            return const FulusLoadingIndicator();
          }
          if (employees.isEmpty) {
            return FulusEmptyState(
              icon: Icons.people_outline,
              headline: 'No team members yet.',
              body: 'Invite your first team member to get started.',
              actionLabel: 'Add team member',
              onAction: () => _openAddSheet(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _EmployeeTile(employee: employees[i]),
          );
        },
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final phoneController = TextEditingController();

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add team member', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.lg),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: roleController, decoration: const InputDecoration(labelText: 'Role (e.g. Cashier)')),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone (optional)')),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: AppTouchTarget.minimum,
                child: FilledButton(
                  onPressed: () async {
                    final repo = ref.read(employeeRepositoryProvider);
                    try {
                      await repo.createEmployee(EmployeeDraft(
                        fullName: nameController.text,
                        role: roleController.text.trim().isEmpty ? null : roleController.text.trim(),
                        phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                      ));
                      if (context.mounted) Navigator.of(context).pop();
                    } on EmployeeValidationException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      // The sheet is built from a `builder:` callback (fresh BuildContext
      // each open), not a State this widget owns, so there's no
      // State.dispose() to hook into — disposing here, once the sheet's
      // own await completes, is what plays that role instead.
      nameController.dispose();
      roleController.dispose();
      phoneController.dispose();
    }
  }
}

class _EmployeeTile extends ConsumerWidget {
  const _EmployeeTile({required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryOf(context).withOpacity(0.1),
                  child: Text(
                    employee.fullName.isNotEmpty ? employee.fullName[0].toUpperCase() : '?',
                    style: TextStyle(color: AppColors.primaryOf(context), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullName,
                        style: AppTypography.body
                            .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                      ),
                      if (employee.role != null)
                        Text(
                          employee.role!,
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                        ),
                    ],
                  ),
                ),
                if (employee.authUserId == null)
                  Tooltip(
                    message: 'No login set up',
                    child: Icon(Icons.no_accounts_outlined, color: AppColors.warningOf(context), size: AppIconSize.compact),
                  ),
                IconButton(
                  icon: const Icon(Icons.event_available_outlined),
                  tooltip: 'Mark attendance',
                  onPressed: () => _markToday(context, ref),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markToday(BuildContext context, WidgetRef ref) async {
    final status = await showModalBottomSheet<AttendanceStatus>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in AttendanceStatus.values)
              ListTile(title: Text(s.name), onTap: () => Navigator.of(context).pop(s)),
          ],
        ),
      ),
    );
    if (status == null) return;
    await ref.read(employeeRepositoryProvider).markAttendance(
          employeeId: employee.id,
          date: DateTime.now(),
          status: status,
        );
  }
}
