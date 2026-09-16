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

typedef _DetailData = ({Employee? employee, AttendanceSummary? attendance, List<LeaveRequest> leaveRequests});

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final repo = ref.read(employeeRepositoryProvider);
    final employee = await repo.getEmployeeById(widget.employeeId, includeInactive: true);
    if (employee == null) return (employee: null, attendance: null, leaveRequests: const <LeaveRequest>[]);
    final now = DateTime.now();
    final results = await Future.wait([
      repo.getAttendanceSummary(employeeId: employee.id, month: now.month, year: now.year),
      repo.listLeaveRequests(employeeId: employee.id),
    ]);
    return (employee: employee, attendance: results[0] as AttendanceSummary, leaveRequests: results[1] as List<LeaveRequest>);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Team member',
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return FulusErrorState(message: "Couldn't load this profile.", onRetry: _reload);
          if (!snap.hasData) return const FulusLoadingIndicator();
          final data = snap.data!;
          final employee = data.employee;
          if (employee == null) return FulusErrorState(message: 'This team member no longer exists.', reassurance: 'They may have been removed.', onRetry: () => context.pop());
          return _EmployeeDetailBody(employee: employee, attendance: data.attendance, leaveRequests: data.leaveRequests, onChanged: _reload);
        },
      ),
    );
  }
}

class _EmployeeDetailBody extends ConsumerWidget {
  const _EmployeeDetailBody({required this.employee, required this.attendance, required this.leaveRequests, required this.onChanged});
  final Employee employee;
  final AttendanceSummary? attendance;
  final List<LeaveRequest> leaveRequests;
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
        FulusCard(child: employee.authUserId != null
            ? Row(children: [Icon(Icons.check_circle_outline, color: AppColors.primaryOf(context)), const SizedBox(width: AppSpacing.sm), Expanded(child: Text('Login active — they can sign in on this device.', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))))])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('No login set up yet — they can\'t sign in until one is created.', style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))), const SizedBox(height: AppSpacing.md), SizedBox(width: double.infinity, child: FulusButton(label: 'Set up login', onPressed: () => _openSetUpLoginSheet(context, ref, grantableBy)))])),
        if (employee.authUserId != null) ...[const SizedBox(height: AppSpacing.lg), FulusSectionHeader(title: 'Access & permissions'), FulusCard(child: _AccessPermissionsSection(authUserId: employee.authUserId!, grantableBy: grantableBy))],
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Attendance this month'),
        FulusCard(child: wide ? Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: _stats(context)) : Wrap(alignment: WrapAlignment.spaceAround, spacing: AppSpacing.xl, runSpacing: AppSpacing.md, children: _stats(context))),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Leave requests'),
        if (leaveRequests.isEmpty) FulusEmptyState(icon: Icons.event_busy_outlined, headline: 'No leave requests.') else ...[
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
  void initState() { super.initState(); _load(); }
  void _load() { _future = ref.read(permissionRepositoryProvider).getPermissions(widget.authUserId).then((stored) { _editing = Set<Permission>.of(stored); return stored; }); }
  Future<void> _save() async {
    final acting = ref.read(sessionProvider); if (acting == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(permissionRepositoryProvider).setPermissions(userId: widget.authUserId, permissions: _editing, grantedBy: acting.id);
      if (!mounted) return;
      ref.invalidate(sessionPermissionsProvider);
      setState(() { _saving = false; _load(); });
      showFulusSnackbar(context, message: 'Permissions updated.');
    } on Failure catch (f) { if (mounted) setState(() { _saving = false; _error = f.message; }); }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Set<Permission>>(future: _future, builder: (context, snapshot) {
    if (!snapshot.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator()));
    final stored = snapshot.data!; final dirty = !setEquals(stored, _editing);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
      PermissionEditor(selected: _editing, grantableBy: widget.grantableBy, onChanged: (next) => setState(() => _editing = next)),
      if (dirty) ...[const SizedBox(height: AppSpacing.sm), Row(children: [Expanded(child: OutlinedButton(onPressed: _saving ? null : () => setState(() => _editing = Set<Permission>.of(stored)), child: const Text('Cancel'))), const SizedBox(width: AppSpacing.sm), Expanded(child: FulusButton(label: 'Save changes', loading: _saving, onPressed: _saving ? null : _save))])],
    ]);
  });
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
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [compact ? Row(children: [Expanded(child: dates), const SizedBox(width: AppSpacing.sm), status]) : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [dates, status]), if (leave.reason != null && leave.reason!.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(leave.reason!, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)))], if (leave.status == LeaveStatus.pending) ...[const SizedBox(height: AppSpacing.sm), Row(children: [Expanded(child: FulusButton(label: 'Deny', variant: FulusButtonVariant.secondary, onPressed: () => _decide(context, ref, LeaveStatus.denied))), const SizedBox(width: AppSpacing.sm), Expanded(child: FulusButton(label: 'Approve', onPressed: () => _decide(context, ref, LeaveStatus.approved)))])]);
    })));
  }
  Future<void> _decide(BuildContext context, WidgetRef ref, LeaveStatus status) async {
    final decidedBy = ref.read(authRepositoryProvider).currentUser?.id; if (decidedBy == null) return;
    try { await ref.read(employeeRepositoryProvider).decideLeaveRequest(leaveId: leave.id, status: status, decidedBy: decidedBy); onChanged(); }
    on Failure catch (f) { if (context.mounted) showFulusSnackbar(context, message: f.message); }
    catch (_) { if (context.mounted) showFulusSnackbar(context, message: "That request isn't available anymore."); onChanged(); }
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
