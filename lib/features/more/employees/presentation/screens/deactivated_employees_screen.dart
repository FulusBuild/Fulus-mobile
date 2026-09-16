import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

class DeactivatedEmployeesScreen extends ConsumerStatefulWidget {
  const DeactivatedEmployeesScreen({super.key});
  @override
  ConsumerState<DeactivatedEmployeesScreen> createState() => _DeactivatedEmployeesScreenState();
}

class _DeactivatedEmployeesScreenState extends ConsumerState<DeactivatedEmployeesScreen> {
  late final Stream<List<Employee>> _employeesStream = ref.read(employeeRepositoryProvider).watchEmployees(isActive: false);

  @override
  Widget build(BuildContext context) => FulusScreen(
        title: 'Deactivated team members',
        subtitle: 'People no longer active in your workspace',
        body: StreamBuilder<List<Employee>>(
          stream: _employeesStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const FulusLoadingIndicator();
            final employees = snapshot.data!;
            if (employees.isEmpty) return const FulusEmptyState(icon: Icons.people_outline, headline: 'No deactivated team members', body: 'Deactivated members appear here and can be reactivated from their profile.');
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.lg),
              itemCount: employees.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) {
                final employee = employees[i];
                return FulusCard(
                  onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
                  child: Row(children: [
                    FulusAvatar(name: employee.fullName),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(employee.fullName, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
                      if (employee.role != null) Text(employee.role!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                    ])),
                    Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                  ]),
                );
              },
            );
          },
        ),
      );
}
