import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../domain/entities/permission.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../widgets/permission_editor.dart';

/// Employee detail workspace. Existing login, permission, attendance,
/// leave-review, and access-management behavior is preserved; this screen
/// only provides the modern responsive presentation around those flows.
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

typedef _RelatedDetailData = ({AttendanceSummary attendance, List<LeaveRequest> leaveRequests});

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  late Future<Employee?> _employeeFuture;
  Future<_RelatedDetailData>? _relatedFuture;
  Employee? _visibleEmployee;

  @override
  void initState() {
    super.initState();
    _employeeFuture = _loadEmployee();
    _employeeFuture.then((employee) {
      if (mounted && employee != null) setState(() => _visibleEmployee = employee);
    }, onError: (_) {});
  }

  Future<Employee?> _loadEmployee() {
    return ref.read(employeeRepositoryProvider).getEmployeeById(widget.employeeId, includeInactive: true);
  }

  Future<_RelatedDetailData> _loadRelatedData(String employeeId) async {
    final repo = ref.read(employeeRepositoryProvider);
    final now = DateTime.now();
    final results = await Future.wait([
      repo.getAttendanceSummary(employeeId: employeeId, month: now.month, year: now.year),
      repo.listLeaveRequests(employeeId: employeeId),
    ]);
    return (attendance: results[0] as AttendanceSummary, leaveRequests: results[1] as List<LeaveRequest>);
  }

  void _reload() {
    final future = _loadEmployee();
    setState(() {
      _employeeFuture = future;
      _relatedFuture = null;
    });
    future.then((employee) {
      if (mounted && employee != null) setState(() => _visibleEmployee = employee);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Team member',
      body: FutureBuilder<Employee?>(
        future: _employeeFuture,
        builder: (context, snap) {
          if (snap.hasError && _visibleEmployee == null) return FulusErrorState(message: "Couldn't load this profile.", onRetry: _reload);
          if (!snap.hasData && _visibleEmployee == null) return const _EmployeeDetailSkeleton();
          if (snap.connectionState == ConnectionState.done && !snap.hasData) return FulusErrorState(message: 'This team member no longer exists.', reassurance: 'They may have been removed.', onRetry: () => context.pop());
          final employee = snap.hasData ? snap.data : _visibleEmployee;
          if (employee == null) return FulusErrorState(message: 'This team member no longer exists.', reassurance: 'They may have been removed.', onRetry: () => context.pop());

          _relatedFuture ??= _loadRelatedData(employee.id);
          return FutureBuilder<_RelatedDetailData>(
            future: _relatedFuture,
            builder: (context, relatedSnap) {
              final attendance = relatedSnap.data?.attendance;
              final leaveRequests = relatedSnap.data?.leaveRequests ?? const <LeaveRequest>[];
              if (relatedSnap.hasError) {
                return _EmployeeDetailBody(
                  employee: employee,
                  attendance: attendance,
                  leaveRequests: leaveRequests,
                  relatedLoading: false,
                  relatedError: true,
                  onChanged: _reload,
                );
              }
              return _EmployeeDetailBody(
                employee: employee,
                attendance: attendance,
                leaveRequests: leaveRequests,
                relatedLoading: !relatedSnap.hasData,
                relatedError: false,
                onChanged: _reload,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmployeeDetailBody extends ConsumerWidget {
  const _EmployeeDetailBody({
    required this.employee,
    required this.attendance,
    required this.leaveRequests,
    required this.relatedLoading,
    required this.relatedError,
    required this.onChanged,
  });
  final Employee employee;
  final AttendanceSummary? attendance;
  final List<LeaveRequest> leaveRequests;
  final bool relatedLoading;
  final bool relatedError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = leaveRequests.where((l) => l.status == LeaveStatus.pending).toList();
    final decided = leaveRequests.where((l) => l.status != LeaveStatus.pending).toList();
    final actingIsOwner = ref.watch(sessionProvider)?.role == AuthRole.owner;
    final grantableBy = actingIsOwner ? Permission.all : ref.watch(sessionPermissionsProvider).value ?? const {};

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final inset = wide ? AppSpacing.lg : AppSpacing.sm;
      final content = <Widget>[
        _ProfileHeader(employee: employee),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Device login'),
        FulusCard(
          child: employee.authUserId != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.primaryOf(context)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Login active — they can sign in on this device.',
                            style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _InviteToAnotherPhoneAction(employee: employee),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No login set up yet — they can\'t sign in until one is created.',
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FulusButton(
                        label: 'Set up login',
                        onPressed: () => _openSetUpLoginSheet(context, ref, grantableBy),
                      ),
                    ),
                  ],
                ),
        ),
        if (employee.authUserId != null) ...[const SizedBox(height: AppSpacing.lg), FulusSectionHeader(title: 'Access & permissions'), FulusCard(child: _AccessPermissionsSection(authUserId: employee.authUserId!, grantableBy: grantableBy))],
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Attendance this month'),
        if (relatedError)
          FulusCard(
            child: Text(
              "Couldn't load attendance right now.",
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          )
        else if (relatedLoading)
          const _EmployeeRelatedLoadingCard()
        else
          FulusCard(
            child: wide
                ? Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: _stats(context))
                : Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: AppSpacing.xl,
                    runSpacing: AppSpacing.md,
                    children: _stats(context),
                  ),
          ),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Leave requests'),
        if (relatedError)
          FulusCard(
            child: Text(
              "Couldn't load leave requests right now.",
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          )
        else if (relatedLoading)
          const _EmployeeRelatedLoadingCard()
        else if (leaveRequests.isEmpty)
          const FulusEmptyState(icon: Icons.event_busy_outlined, headline: 'No leave requests.')
        else ...[
          if (pending.isNotEmpty) _LeaveGroupLabel(label: 'Needs review'),
          for (final leave in pending) _LeaveRequestTile(leave: leave, onChanged: onChanged),
          if (decided.isNotEmpty) _LeaveGroupLabel(label: 'History'),
          for (final leave in decided) _LeaveRequestTile(leave: leave, onChanged: onChanged),
        ],
        const SizedBox(height: AppSpacing.xl),
        _AccessAction(employee: employee),
        const SizedBox(height: AppSpacing.xxl),
      ];
      final body = wide ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: Column(children: content))) : Column(children: content);
      return ListView(padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, 0), children: [body]);
    });
  }

  List<Widget> _stats(BuildContext context) => [
        _AttendanceStat(label: 'Present', value: attendance?.present ?? 0, color: AppColors.primaryOf(context)),
        _AttendanceStat(label: 'Late', value: attendance?.late ?? 0, color: AppColors.warningOf(context)),
        _AttendanceStat(label: 'Absent', value: attendance?.absent ?? 0, color: AppColors.errorOf(context)),
      ];

  Future<void> _openSetUpLoginSheet(BuildContext context, WidgetRef ref, Set<Permission> grantableBy) async {
    final actingOwner = ref.read(sessionProvider);
    if (actingOwner != null && !actingOwner.hasLoginPin) {
      final pinSet = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _SetOwnPinSheet());
      if (pinSet != true) return;
    }
    if (!context.mounted) return;
    final createdPin = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => _SetUpLoginSheet(employee: employee, grantableBy: grantableBy));
    if (createdPin == null) return;
    onChanged();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Login created'),
      content: Text('Share the PIN you set with ${employee.fullName} so they can switch to their own account on this device — they\'ll find their name in the "who\'s this?" list.\n\nPIN: $createdPin'),
      actions: [TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: createdPin)), child: const Text('Copy PIN')), FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done'))],
    ));
  }
}

class _InviteToAnotherPhoneAction extends ConsumerStatefulWidget {
  const _InviteToAnotherPhoneAction({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_InviteToAnotherPhoneAction> createState() => _InviteToAnotherPhoneActionState();
}

class _InviteToAnotherPhoneActionState extends ConsumerState<_InviteToAnotherPhoneAction> {
  bool _busy = false;

  Future<void> _invite() async {
    final email = widget.employee.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      showFulusSnackbar(
        context,
        message: 'Add an email address to this employee before inviting them to another phone.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final authUserId = widget.employee.authUserId;
      if (authUserId == null) throw StateError('This employee has no login account.');

      final db = ref.read(databaseProvider);
      final user = await (db.select(db.users)
            ..where((row) => row.localId.equals(authUserId)))
          .getSingleOrNull();
      if (user == null) throw StateError('The employee login is missing locally.');

      final roleName = switch (user.role) {
        AuthRole.manager => 'manager',
        AuthRole.cashier => 'cashier',
        AuthRole.employee => 'cashier',
        AuthRole.owner => throw StateError('Owners cannot be invited as staff.'),
      };

      final localPermissions =
          await ref.read(permissionRepositoryProvider).getPermissions(authUserId);
      final permissionCodes = _cloudPermissionCodes(localPermissions);

      final invite = await ref.read(fulusConnectionStateProvider).createStaffInvite(
            roleName: roleName,
            email: email,
            permissionCodes: permissionCodes,
          );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Invite ready'),
          content: SelectableText(
            'Share this invitation code with ' +
                widget.employee.fullName +
                '. They should use the same email address:\n\n' +
                invite.token,
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: invite.token)),
              child: const Text('Copy code'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on Failure catch (failure) {
      if (mounted) showFulusSnackbar(context, message: failure.message);
    } catch (error) {
      if (mounted) showFulusSnackbar(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          codes.add('business.manage');
        case Permission.viewAuditLog:
          codes.add('audit.read');
      }
    }
    return codes.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FulusButton(
        label: _busy ? 'Preparing invitation…' : 'Set up on another phone',
        loading: _busy,
        onPressed: _busy ? null : _invite,
        icon: Icons.phone_android_rounded,
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.employee});
  final Employee employee;
  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return FulusCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(radius: 30, backgroundColor: primary.withValues(alpha: 0.1), child: Text(employee.fullName.isNotEmpty ? employee.fullName[0].toUpperCase() : '?', style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 22))),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(employee.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))), if (employee.role != null) Text(employee.role!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)))])),
      ]),
      const SizedBox(height: AppSpacing.md),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
        if (employee.phone != null) _InfoPill(icon: Icons.phone_outlined, text: employee.phone!),
        if (employee.email != null) _InfoPill(icon: Icons.email_outlined, text: employee.email!),
        _InfoPill(icon: employee.isActive ? Icons.verified_outlined : Icons.person_off_outlined, text: employee.isActive ? 'Active' : 'Deactivated'),
      ]),
    ]));
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs), decoration: BoxDecoration(color: AppColors.surfaceVariantOf(context), borderRadius: BorderRadius.circular(AppRadius.md)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)), const SizedBox(width: AppSpacing.xs), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))))]));
}

class _AccessPermissionsSection extends ConsumerStatefulWidget {
  const _AccessPermissionsSection({required this.authUserId, required this.grantableBy});
  final String authUserId;
  final Set<Permission> grantableBy;
  @override
  ConsumerState<_AccessPermissionsSection> createState() => _AccessPermissionsSectionState();
}

class _AccessPermissionsSectionState extends ConsumerState<_AccessPermissionsSection> {
  late Future<Set<Permission>> _future;
  Set<Permission> _editing = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(permissionRepositoryProvider).getPermissions(widget.authUserId).then((stored) {
      _editing = Set<Permission>.of(stored);
      return stored;
    });
  }

  Future<void> _save() async {
    final acting = ref.read(sessionProvider);
    if (acting == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final businessId = ref.read(fulusConnectionStateProvider).selectedBusinessId;
      if (businessId != null && _isCloudUserId(widget.authUserId)) {
        await ref.read(fulusStaffAccessApiProvider).setMemberPermissions(
              businessId: businessId,
              userId: widget.authUserId,
              permissionCodes: _cloudPermissionCodes(_editing),
            );
      }

      await ref.read(permissionRepositoryProvider).setPermissions(
            userId: widget.authUserId,
            permissions: _editing,
            grantedBy: acting.id,
          );

      if (!mounted) return;
      ref.invalidate(sessionPermissionsProvider);
      setState(() {
        _saving = false;
        _load();
      });
      showFulusSnackbar(context, message: 'Permissions updated.');
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  bool _isCloudUserId(String value) {
    if (value.length != 36) return false;
    const hyphens = <int>[8, 13, 18, 23];
    for (var i = 0; i < value.length; i++) {
      if (hyphens.contains(i)) {
        if (value.codeUnitAt(i) != 45) return false;
      } else {
        final code = value.codeUnitAt(i);
        final isDigit = code >= 48 && code <= 57;
        final isLower = code >= 97 && code <= 102;
        final isUpper = code >= 65 && code <= 70;
        if (!isDigit && !isLower && !isUpper) return false;
      }
    }
    return true;
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
          codes.add('business.manage');
        case Permission.viewAuditLog:
          codes.add('audit.read');
      }
    }

    return codes.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<Permission>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final stored = snapshot.data!;
        final dirty = !setEquals(stored, _editing);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: AppTypography.body.copyWith(
                  color: AppColors.errorOf(context),
                ),
              ),
            PermissionEditor(
              selected: _editing,
              grantableBy: widget.grantableBy,
              onChanged: (next) => setState(() => _editing = next),
            ),
            if (dirty)
              ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FulusButton(
                        variant: FulusButtonVariant.secondary,
                        onPressed: _saving
                            ? null
                            : () => setState(() => _editing = Set<Permission>.of(stored)),
                        label: 'Cancel',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FulusButton(
                        label: 'Save changes',
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
              ],
          ],
        );
      },
    );
  }
}

class _EmployeeRelatedLoadingCard extends StatelessWidget {
  const _EmployeeRelatedLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FulusSkeletonBox(height: 18, width: 140),
          SizedBox(height: AppSpacing.md),
          FulusSkeletonBox(height: 52),
        ],
      ),
    );
  }
}

class _AttendanceStat extends StatelessWidget {
  const _AttendanceStat({required this.label, required this.value, required this.color});
  final String label; final int value; final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [Text('$value', style: AppTypography.display.copyWith(color: color)), const SizedBox(height: AppSpacing.xs), Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)))]);
}

class _LeaveGroupLabel extends StatelessWidget {
  const _LeaveGroupLabel({required this.label}); final String label;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs), child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700)));
}

class _LeaveRequestTile extends ConsumerWidget {
  const _LeaveRequestTile({required this.leave, required this.onChanged});
  final LeaveRequest leave; final VoidCallback onChanged;
  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = switch (leave.status) { LeaveStatus.pending => ('Pending', AppColors.warningOf(context)), LeaveStatus.approved => ('Approved', AppColors.primaryOf(context)), LeaveStatus.denied => ('Denied', AppColors.errorOf(context)) };
    return Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: FulusCard(child: LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 440;
      final status = Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)), child: Text(label, style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600)));
      final dates = Text('${_fmt(leave.startDate)} – ${_fmt(leave.endDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          compact
              ? Row(children: [Expanded(child: dates), const SizedBox(width: AppSpacing.sm), status])
              : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [dates, status]),
          if (leave.reason != null && leave.reason!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(leave.reason!, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          ],
          if (leave.status == LeaveStatus.pending) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(child: FulusButton(label: 'Deny', variant: FulusButtonVariant.secondary, onPressed: () => _decide(context, ref, LeaveStatus.denied))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: FulusButton(label: 'Approve', onPressed: () => _decide(context, ref, LeaveStatus.approved))),
            ]),
          ],
        ],
      );
    })));
  }
  Future<void> _decide(BuildContext context, WidgetRef ref, LeaveStatus status) async {
    final decidedBy = ref.read(authRepositoryProvider).currentUser?.id; if (decidedBy == null) return;
    try { await ref.read(employeeRepositoryProvider).decideLeaveRequest(leaveId: leave.id, status: status, decidedBy: decidedBy); onChanged(); }
    on Failure catch (f) { if (context.mounted) showFulusSnackbar(context, message: f.message); }
    on Object catch (_) { if (context.mounted) showFulusSnackbar(context, message: "That request isn't available anymore."); onChanged(); }
  }
}

class _AccessAction extends ConsumerWidget {
  const _AccessAction({required this.employee}); final Employee employee;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(children: [SizedBox(width: double.infinity, child: FulusButton(label: employee.isActive ? 'Deactivate this team member' : 'Reactivate this team member', variant: employee.isActive ? FulusButtonVariant.destructive : FulusButtonVariant.secondary, onPressed: () => employee.isActive ? _deactivate(context, ref) : _reactivate(context, ref))), const SizedBox(height: AppSpacing.sm), Text(employee.isActive ? "They'll no longer be able to sign in, and will disappear from the active roster. Their history is kept, and this can be undone at any time." : "They'll be restored to the active roster and, if they had a login, able to sign in again.", style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)), textAlign: TextAlign.center)]);
  Future<void> _deactivate(BuildContext context, WidgetRef ref) async { final confirmed = await showFulusConfirmDialog(context, title: 'Deactivate ${employee.fullName}?', message: '${employee.fullName} will immediately lose access to sign in on this device. You can reactivate them any time.', confirmLabel: 'Deactivate'); if (!confirmed || !context.mounted) return; try { await ref.read(employeeRepositoryProvider).deactivateEmployee(employee.id); if (context.mounted) { showFulusSnackbar(context, message: '${employee.fullName} was deactivated.'); context.pop(); } } catch (_) { if (context.mounted) showFulusSnackbar(context, message: "Couldn't deactivate ${employee.fullName}. Try again."); } }
  Future<void> _reactivate(BuildContext context, WidgetRef ref) async { try { await ref.read(employeeRepositoryProvider).reactivateEmployee(employee.id); if (context.mounted) { showFulusSnackbar(context, message: '${employee.fullName} was reactivated.'); context.pop(); } } catch (_) { if (context.mounted) showFulusSnackbar(context, message: "Couldn't reactivate ${employee.fullName}. Try again."); } }
}

class _SetOwnPinSheet extends ConsumerStatefulWidget {
  const _SetOwnPinSheet();
  @override ConsumerState<_SetOwnPinSheet> createState() => _SetOwnPinSheetState();
}
class _SetOwnPinSheetState extends ConsumerState<_SetOwnPinSheet> {
  final _pinController = TextEditingController(); final _confirmController = TextEditingController(); Map<String, String> _errors = {}; bool _submitting = false;
  @override void dispose() { _pinController.dispose(); _confirmController.dispose(); super.dispose(); }
  Future<void> _submit() async { final pin = _pinController.text.trim(); final errors = <String, String>{}; if (pin.length < 4) errors['pin'] = 'Use at least 4 digits.'; if (_confirmController.text.trim() != pin) errors['confirm'] = "PINs don't match."; if (errors.isNotEmpty) { setState(() => _errors = errors); return; } setState(() { _submitting = true; _errors = {}; }); try { await ref.read(authRepositoryProvider).setOwnLoginPin(pin: pin); final updated = ref.read(sessionProvider); if (updated != null) ref.read(sessionProvider.notifier).state = AuthUser(id: updated.id, username: updated.username, email: updated.email, fullName: updated.fullName, role: updated.role, isActive: updated.isActive, hasLoginPin: true); if (mounted) Navigator.of(context).pop(true); } on Failure catch (f) { if (mounted) setState(() { _submitting = false; _errors = {'form': f.message}; }); } }
  @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg, bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Set your own PIN first', style: AppTypography.heading), const SizedBox(height: AppSpacing.xs), Text("You'll use this to switch back to your own account once someone else has one on this device.", style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))), const SizedBox(height: AppSpacing.lg), if (_errors['form'] != null) Text(_errors['form']!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))), FulusTextField(label: 'Your PIN', controller: _pinController, obscureText: true, keyboardType: TextInputType.number, errorText: _errors['pin'], helperText: 'At least 4 digits.'), const SizedBox(height: AppSpacing.sm), FulusTextField(label: 'Confirm PIN', controller: _confirmController, obscureText: true, keyboardType: TextInputType.number, errorText: _errors['confirm']), const SizedBox(height: AppSpacing.lg), SizedBox(width: double.infinity, child: FulusButton(label: 'Save PIN', loading: _submitting, onPressed: _submitting ? null : _submit))])));
}

class _SetUpLoginSheet extends ConsumerStatefulWidget {
  const _SetUpLoginSheet({required this.employee, required this.grantableBy});
  final Employee employee; final Set<Permission> grantableBy;
  @override ConsumerState<_SetUpLoginSheet> createState() => _SetUpLoginSheetState();
}
class _SetUpLoginSheetState extends ConsumerState<_SetUpLoginSheet> {
  final _pinController = TextEditingController(); final _confirmController = TextEditingController(); Map<String, String> _errors = {}; bool _submitting = false; AuthRolePreset _preset = AuthRolePreset.cashier; Set<Permission> _permissions = {}; bool _permissionsCustomized = false;
  @override void initState() { super.initState(); _permissions = _defaultsWithinGrant(AuthRole.cashier); }
  Set<Permission> _defaultsWithinGrant(AuthRole role) => Permission.defaultsForRole(role).intersection(widget.grantableBy);
  @override void dispose() { _pinController.dispose(); _confirmController.dispose(); super.dispose(); }
  void _onPresetChanged(AuthRolePreset preset) { setState(() { _preset = preset; if (!_permissionsCustomized) _permissions = _defaultsWithinGrant(preset.role); }); }
  Future<void> _submit() async { final pin = _pinController.text.trim(); final errors = <String, String>{}; if (pin.length < 4) errors['pin'] = 'Use at least 4 digits.'; if (_confirmController.text.trim() != pin) errors['confirm'] = "PINs don't match."; if (errors.isNotEmpty) { setState(() => _errors = errors); return; } setState(() { _submitting = true; _errors = {}; }); try { final acting = ref.read(sessionProvider); final created = await ref.read(authRepositoryProvider).createEmployeeAccount(employeeId: widget.employee.id, pin: pin, role: _preset.role); if (acting != null) await ref.read(permissionRepositoryProvider).setPermissions(userId: created.id, permissions: _permissions, grantedBy: acting.id); if (mounted) Navigator.of(context).pop(pin); } on Failure catch (f) { if (mounted) setState(() { _submitting = false; _errors = {'form': f.message}; }); } }
  @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg, bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Set up login for ${widget.employee.fullName}', style: AppTypography.heading), const SizedBox(height: AppSpacing.xs), Text("They'll use this PIN to switch to their own account on this device.", style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))), const SizedBox(height: AppSpacing.lg), if (_errors['form'] != null) Text(_errors['form']!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))), FulusTextField(label: 'PIN', controller: _pinController, obscureText: true, keyboardType: TextInputType.number, errorText: _errors['pin'], helperText: 'At least 4 digits.'), const SizedBox(height: AppSpacing.sm), FulusTextField(label: 'Confirm PIN', controller: _confirmController, obscureText: true, keyboardType: TextInputType.number, errorText: _errors['confirm']), const SizedBox(height: AppSpacing.lg), Text('Role', style: AppTypography.subheading), const SizedBox(height: AppSpacing.xs), RolePresetSelector(selected: _preset, onChanged: _onPresetChanged), const SizedBox(height: AppSpacing.md), Text('Permissions', style: AppTypography.subheading), Text('Starts from the role above — adjust anything before creating the login.', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))), PermissionEditor(selected: _permissions, grantableBy: widget.grantableBy, onChanged: (next) => setState(() { _permissions = next; _permissionsCustomized = true; })), const SizedBox(height: AppSpacing.lg), SizedBox(width: double.infinity, child: FulusButton(label: 'Create login', loading: _submitting, onPressed: _submitting ? null : _submit))])));
}

class _EmployeeDetailSkeleton extends StatelessWidget {
  const _EmployeeDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xxl),
      children: const [
        FulusCardSkeleton(),
        SizedBox(height: AppSpacing.lg),
        FulusSkeletonBox(height: 18, width: 120),
        SizedBox(height: AppSpacing.sm),
        FulusSkeletonBox(height: 84, borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
        SizedBox(height: AppSpacing.lg),
        FulusSkeletonBox(height: 18, width: 150),
        SizedBox(height: AppSpacing.sm),
        FulusSkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
        SizedBox(height: AppSpacing.lg),
        FulusSkeletonBox(height: 18, width: 120),
        SizedBox(height: AppSpacing.sm),
        FulusListRowSkeleton(hasLeading: false),
        FulusListRowSkeleton(hasLeading: false),
        FulusListRowSkeleton(hasLeading: false),
      ],
    );
  }
}
