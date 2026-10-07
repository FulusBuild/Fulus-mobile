import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/async_timeout.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

class DeactivatedEmployeesScreen extends ConsumerStatefulWidget {
  const DeactivatedEmployeesScreen({super.key});
  @override
  ConsumerState<DeactivatedEmployeesScreen> createState() => _DeactivatedEmployeesScreenState();
}

class _DeactivatedEmployeesScreenState extends ConsumerState<DeactivatedEmployeesScreen> {
  late Stream<List<Employee>> _employeesStream;

  @override
  void initState() {
    super.initState();
    _employeesStream = ref.read(employeeRepositoryProvider).watchEmployees(isActive: false);
  }

  @override
  Widget build(BuildContext context) => FulusScreen(
        title: 'Deactivated team members',
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final inset = wide ? AppSpacing.xl : AppSpacing.md;
            final contentWidth = wide ? 760.0 : double.infinity;

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: StreamBuilder<List<Employee>>(
                  stream: _employeesStream.withFulusLoadingTimeout(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return FulusErrorState(
                        message: "Couldn't load deactivated team members.",
                        reassurance: 'No team data was changed — this is only a loading problem.',
                        onRetry: () => setState(() {
                          _employeesStream = ref.read(employeeRepositoryProvider).watchEmployees(isActive: false);
                        }),
                      );
                    }
                    if (!snapshot.hasData) return const _DeactivatedEmployeesLoadingSkeleton();
                    final employees = snapshot.data!;
                    if (employees.isEmpty) {
                      return const FulusEmptyState(
                        icon: Icons.people_outline,
                        headline: 'No deactivated team members',
                        body: 'Deactivated members appear here and can be reactivated from their profile.',
                      );
                    }
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.lg),
                      itemCount: employees.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final employee = employees[i];
                        return FulusListRow(
                          leading: FulusAvatar(name: employee.fullName),
                          title: Text(employee.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: employee.role == null ? null : Text(employee.role!),
                          onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': employee.id}),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
      );
}
class _DeactivatedEmployeesLoadingSkeleton extends StatelessWidget {
  const _DeactivatedEmployeesLoadingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.sm),
    children: const [
      FulusCardSkeleton(),
      SizedBox(height: AppSpacing.sm),
      FulusListRowSkeleton(hasLeading: true),
      FulusListRowSkeleton(hasLeading: true),
      FulusListRowSkeleton(hasLeading: true),
    ],
  );
}
