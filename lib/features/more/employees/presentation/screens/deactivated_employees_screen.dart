import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Reached from EmployeesListScreen's own AppBar action. Exists purely
/// so a deactivated employee is reachable at all — the main roster
/// only ever shows `isActive: true` — and taps into the same
/// EmployeeDetailScreen every active employee uses, where reactivating
/// actually happens; this screen is a list, not its own action.
class DeactivatedEmployeesScreen extends ConsumerStatefulWidget {
  const DeactivatedEmployeesScreen({super.key});

  @override
  ConsumerState<DeactivatedEmployeesScreen> createState() => _DeactivatedEmployeesScreenState();
}

class _DeactivatedEmployeesScreenState extends ConsumerState<DeactivatedEmployeesScreen> {
  late final Stream<List<Employee>> _employeesStream =
      ref.read(employeeRepositoryProvider).watchEmployees(isActive: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(title: const Text('Deactivated team members')),
      body: StreamBuilder<List<Employee>>(
        stream: _employeesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const FulusLoadingIndicator();
          final employees = snapshot.data!;
          if (employees.isEmpty) {
            return const FulusEmptyState(
              icon: Icons.people_outline,
              headline: 'No deactivated team members.',
              body: 'Anyone you deactivate shows up here, and can be reactivated any time.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final employee = employees[i];
              return FulusCard(
                onTap: () => context.pushNamed(
                  'moreEmployeeDetail',
                  pathParameters: {'employeeId': employee.id},
                ),
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
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          if (employee.role != null)
                            Text(
                              employee.role!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
