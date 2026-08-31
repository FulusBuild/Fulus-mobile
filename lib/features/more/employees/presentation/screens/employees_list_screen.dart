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
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          FulusIconButton(
            icon: Icons.person_off_outlined,
            tooltip: 'Deactivated team members',
            onPressed: () => context.pushNamed('moreEmployeesDeactivated'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add member'),
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

  Future<void> _openAddSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddEmployeeSheet(),
    );
  }
}

/// A proper `StatefulWidget` so its `TextEditingController`s are owned
/// and disposed by `State.dispose()` — i.e. only once this sheet's
/// element is actually removed from the tree, after its close
/// animation finishes.
///
/// CORRECTED: this used to be a `builder:` closure with three
/// controllers created as local variables and disposed in a `finally`
/// the instant `showModalBottomSheet`'s Future resolved — which fires
/// on `Navigator.pop()`, *before* the sheet's slide-down exit
/// animation finishes, while its `FulusTextField`s (still bound to
/// those now-disposed controllers) were still mounted and potentially
/// still focused. That's what was producing the diagnostics report's
/// `_batchEditDepth <= 0` assertion and "A TextEditingController was
/// used after being disposed." — confirmed against `_SetUpLoginSheet`
/// below, which already used this correct pattern.
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
    final repo = ref.read(employeeRepositoryProvider);
    setState(() => _saving = true);
    try {
      await repo.createEmployee(EmployeeDraft(
        fullName: _nameController.text,
        role: _roleController.text.trim().isEmpty ? null : _roleController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      ));
      if (mounted) Navigator.of(context).pop();
    } on EmployeeValidationException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFulusSnackbar(context, message: e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      // Responsive UI audit — SingleChildScrollView added; same gap as
      // DiscountSheet (see that file's comment): a direct
      // showModalBottomSheet call, bare Column, three text fields whose
      // keyboard will eat into the available height once focused.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add team member', style: AppTypography.heading),
            const SizedBox(height: AppSpacing.lg),
            FulusTextField(label: 'Full name', controller: _nameController),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Role (e.g. Cashier)', controller: _roleController),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Phone (optional)', controller: _phoneController, keyboardType: TextInputType.phone),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Add',
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
  const _EmployeeTile({required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusCard(
      onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
      child: Row(
        children: [
          FulusAvatar(name: employee.fullName),
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
