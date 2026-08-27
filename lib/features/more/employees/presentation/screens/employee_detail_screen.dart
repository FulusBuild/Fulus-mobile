import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/employee.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Gap fix — three items from the audit land on one screen because
/// they're really one story (an owner looking at one team member):
///
/// 1. "No employee detail screen" — tapping a roster row did nothing.
/// 2. "No way to revoke access" — [EmployeeRepository.deactivateEmployee]
///    already existed with no caller anywhere in the UI.
/// 3. "Leave Request Review" — explicitly flagged in
///    employees_list_screen.dart's own header comment as left for a
///    follow-on screen; the repository/engine side was already done.
///
/// Also closes the credential gap noted in the audit: "Add team member"
/// only ever created an HR roster row (Employee) — a fully separate
/// concept from a device login (AuthUser; see employee.dart's own class
/// doc). `AuthRepository.createEmployeeAccount` already existed to link
/// the two but had no caller anywhere. The "Set up login" card below is
/// that missing caller.
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

typedef _DetailData = ({
  Employee? employee,
  AttendanceSummary? attendance,
  List<LeaveRequest> leaveRequests,
});

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
    if (employee == null) {
      return (employee: null, attendance: null, leaveRequests: const <LeaveRequest>[]);
    }
    final now = DateTime.now();
    final results = await Future.wait([
      repo.getAttendanceSummary(employeeId: employee.id, month: now.month, year: now.year),
      repo.listLeaveRequests(employeeId: employee.id),
    ]);
    return (
      employee: employee,
      attendance: results[0] as AttendanceSummary,
      leaveRequests: results[1] as List<LeaveRequest>,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Team member',
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(message: "Couldn't load this profile.", onRetry: _reload);
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final data = snap.data!;
          final employee = data.employee;
          if (employee == null) {
            return FulusErrorState(
              message: 'This team member no longer exists.',
              reassurance: 'They may have been removed.',
              onRetry: () => context.pop(),
            );
          }
          return _EmployeeDetailBody(
            employee: employee,
            attendance: data.attendance,
            leaveRequests: data.leaveRequests,
            onChanged: _reload,
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
    required this.onChanged,
  });

  final Employee employee;
  final AttendanceSummary? attendance;
  final List<LeaveRequest> leaveRequests;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = leaveRequests.where((l) => l.status == LeaveStatus.pending).toList();
    final decided = leaveRequests.where((l) => l.status != LeaveStatus.pending).toList();

    return ListView(
      children: [
        FulusCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryOf(context).withValues(alpha: 0.1),
                child: Text(
                  employee.fullName.isNotEmpty ? employee.fullName[0].toUpperCase() : '?',
                  style: TextStyle(color: AppColors.primaryOf(context), fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
                    ),
                    if (employee.role != null)
                      Text(employee.role!, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
                    if (employee.phone != null)
                      Text(employee.phone!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                    if (employee.email != null)
                      Text(employee.email!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Login ──────────────────────────────────────────────────────
        FulusSectionHeader(title: 'Device login'),
        FulusCard(
          child: employee.authUserId != null
              ? Row(
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
                        onPressed: () => _openSetUpLoginSheet(context, ref),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Attendance ─────────────────────────────────────────────────
        FulusSectionHeader(title: 'Attendance this month'),
        FulusCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _AttendanceStat(label: 'Present', value: attendance?.present ?? 0, color: AppColors.primaryOf(context)),
              _AttendanceStat(label: 'Late', value: attendance?.late ?? 0, color: AppColors.warningOf(context)),
              _AttendanceStat(label: 'Absent', value: attendance?.absent ?? 0, color: AppColors.errorOf(context)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Leave requests ─────────────────────────────────────────────
        FulusSectionHeader(title: 'Leave requests'),
        if (leaveRequests.isEmpty)
          FulusEmptyState(icon: Icons.event_busy_outlined, headline: 'No leave requests.')
        else ...[
          for (final leave in pending) _LeaveRequestTile(leave: leave, onChanged: onChanged),
          for (final leave in decided) _LeaveRequestTile(leave: leave, onChanged: onChanged),
        ],
        const SizedBox(height: AppSpacing.xxl),

        // ── Deactivate / Reactivate ──────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FulusButton(
            label: employee.isActive ? 'Deactivate this team member' : 'Reactivate this team member',
            variant: employee.isActive ? FulusButtonVariant.destructive : FulusButtonVariant.secondary,
            onPressed: () => employee.isActive ? _deactivate(context, ref) : _reactivate(context, ref),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          employee.isActive
              ? "They'll no longer be able to sign in, and will disappear from the "
                  'active roster. Their sales and attendance history is kept, and this '
                  'can be undone at any time.'
              : "They'll be restored to the active roster and, if they had a login, "
                  'able to sign in again.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Deactivate ${employee.fullName}?',
      message: '${employee.fullName} will immediately lose access to sign in on this device. '
          "You can reactivate them from this same screen any time — nothing here is permanent.",
      confirmLabel: 'Deactivate',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(employeeRepositoryProvider).deactivateEmployee(employee.id);
      if (context.mounted) {
        showFulusSnackbar(context, message: '${employee.fullName} was deactivated.');
        context.pop();
      }
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't deactivate ${employee.fullName}. Try again.");
      }
    }
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(employeeRepositoryProvider).reactivateEmployee(employee.id);
      if (context.mounted) {
        showFulusSnackbar(context, message: '${employee.fullName} was reactivated.');
        context.pop();
      }
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't reactivate ${employee.fullName}. Try again.");
      }
    }
  }

  Future<void> _openSetUpLoginSheet(BuildContext context, WidgetRef ref) async {
    // See setOwnLoginPin's own doc comment on AuthRepository — an owner
    // can't provision someone else's PIN before choosing their own
    // first. Checked here, not just left to createEmployeeAccount's own
    // enforcement, so the owner gets a real next step instead of a
    // banner explaining why "Create login" failed.
    final actingOwner = ref.read(sessionProvider);
    if (actingOwner != null && !actingOwner.hasLoginPin) {
      final pinSet = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => const _SetOwnPinSheet(),
      );
      if (pinSet != true) return;
    }
    if (!context.mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _SetUpLoginSheet(employee: employee),
    );
    if (created == true) onChanged();
  }
}

class _AttendanceStat extends StatelessWidget {
  const _AttendanceStat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: AppTypography.display.copyWith(color: color)),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      ],
    );
  }
}

class _LeaveRequestTile extends ConsumerWidget {
  const _LeaveRequestTile({required this.leave, required this.onChanged});
  final LeaveRequest leave;
  final VoidCallback onChanged;

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = switch (leave.status) {
      LeaveStatus.pending => ('Pending', AppColors.warningOf(context)),
      LeaveStatus.approved => ('Approved', AppColors.primaryOf(context)),
      LeaveStatus.denied => ('Denied', AppColors.errorOf(context)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FulusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_fmt(leave.startDate)} – ${_fmt(leave.endDate)}',
                  style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (leave.reason != null && leave.reason!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(leave.reason!, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
            ],
            if (leave.status == LeaveStatus.pending) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FulusButton(
                      label: 'Deny',
                      variant: FulusButtonVariant.secondary,
                      onPressed: () => _decide(context, ref, LeaveStatus.denied),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FulusButton(
                      label: 'Approve',
                      onPressed: () => _decide(context, ref, LeaveStatus.approved),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, LeaveStatus status) async {
    final decidedBy = ref.read(authRepositoryProvider).currentUser?.id;
    if (decidedBy == null) return;
    try {
      await ref.read(employeeRepositoryProvider).decideLeaveRequest(
            leaveId: leave.id,
            status: status,
            decidedBy: decidedBy,
          );
      onChanged();
    } on Failure catch (f) {
      if (context.mounted) showFulusSnackbar(context, message: f.message);
    } catch (_) {
      // decideLeaveRequest can throw a raw StateError if this request
      // was removed or already decided elsewhere between this list
      // loading and this tap — not a Failure (see repository impl), so
      // caught separately here rather than left unhandled.
      if (context.mounted) {
        showFulusSnackbar(context, message: "That request isn't available anymore.");
        onChanged();
      }
    }
  }
}

/// setOwnLoginPin's own required precondition for
/// createAdditionalOwner/createEmployeeAccount, surfaced as a real step
/// rather than a dead-end error — see _openSetUpLoginSheet above. Not
/// employee-specific despite living in this file: an owner sets THEIR
/// OWN PIN here regardless of which flow (co-owner or employee)
/// prompted it, so it stays generic rather than named after either.
class _SetOwnPinSheet extends ConsumerStatefulWidget {
  const _SetOwnPinSheet();

  @override
  ConsumerState<_SetOwnPinSheet> createState() => _SetOwnPinSheetState();
}

class _SetOwnPinSheetState extends ConsumerState<_SetOwnPinSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  Map<String, String> _errors = {};
  bool _submitting = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    final errors = <String, String>{};
    if (pin.length < 4) errors['pin'] = 'Use at least 4 digits.';
    if (_confirmController.text.trim() != pin) errors['confirm'] = "PINs don't match.";
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _submitting = true;
      _errors = {};
    });
    try {
      await ref.read(authRepositoryProvider).setOwnLoginPin(pin: pin);
      final updated = ref.read(sessionProvider);
      if (updated != null) {
        ref.read(sessionProvider.notifier).state = AuthUser(
          id: updated.id,
          username: updated.username,
          email: updated.email,
          fullName: updated.fullName,
          role: updated.role,
          isActive: updated.isActive,
          hasLoginPin: true,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errors = {'form': f.message};
      });
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set your own PIN first', style: AppTypography.heading),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "You'll use this to switch back to your own account once "
            "someone else has one on this device.",
            style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errors['form'] != null) ...[
            Text(_errors['form']!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
            const SizedBox(height: AppSpacing.sm),
          ],
          FulusTextField(
            label: 'Your PIN',
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            errorText: _errors['pin'],
            helperText: 'At least 4 digits.',
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusTextField(
            label: 'Confirm PIN',
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            errorText: _errors['confirm'],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FulusButton(label: 'Save PIN', loading: _submitting, onPressed: _submitting ? null : _submit),
          ),
        ],
      ),
    );
  }
}

/// The missing "Add team member" → login link. Onboarding-simplification
/// pass: collects a PIN instead of username/email/password — see
/// AuthRepository.createEmployeeAccount's own doc comment for why.
class _SetUpLoginSheet extends ConsumerStatefulWidget {
  const _SetUpLoginSheet({required this.employee});
  final Employee employee;

  @override
  ConsumerState<_SetUpLoginSheet> createState() => _SetUpLoginSheetState();
}

class _SetUpLoginSheetState extends ConsumerState<_SetUpLoginSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  Map<String, String> _errors = {};
  bool _submitting = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();

    final errors = <String, String>{};
    if (pin.length < 4) errors['pin'] = 'Use at least 4 digits.';
    if (_confirmController.text.trim() != pin) {
      errors['confirm'] = "PINs don't match.";
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _submitting = true;
      _errors = {};
    });
    try {
      await ref.read(authRepositoryProvider).createEmployeeAccount(
            employeeId: widget.employee.id,
            pin: pin,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      // The owner just chose this PIN themselves (this isn't a
      // generated secret to reveal) — this confirmation is about making
      // the handoff moment explicit, since nothing in this app told
      // anyone to do this before now.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Login created'),
          content: Text(
            'Share the PIN you set with ${widget.employee.fullName} so '
            'they can switch to their own account on this device — they\'ll '
            'find their name in the "who\'s this?" list.\n\nPIN: $pin',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pin));
              },
              child: const Text('Copy PIN'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errors = {'form': f.message};
      });
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up login for ${widget.employee.fullName}', style: AppTypography.heading),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "They'll use this PIN to switch to their own account on this device.",
            style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errors['form'] != null) ...[
            Text(_errors['form']!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
            const SizedBox(height: AppSpacing.sm),
          ],
          FulusTextField(
            label: 'PIN',
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            errorText: _errors['pin'],
            helperText: 'At least 4 digits.',
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusTextField(
            label: 'Confirm PIN',
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            errorText: _errors['confirm'],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FulusButton(label: 'Create login', loading: _submitting, onPressed: _submitting ? null : _submit),
          ),
        ],
      ),
    );
  }
}
