import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../sync/sync_user_message.dart';

/// Replaces the pre-simplification SignInScreen entirely — see
/// AuthRepository.switchLocalUser's own doc comment for why a
/// username+password form no longer applies to same-device sign-in.
/// Shown by [AuthGateScreen] for [AuthGateStage.needsSignIn].
class IdentityPickerScreen extends ConsumerStatefulWidget {
  const IdentityPickerScreen({super.key});

  @override
  ConsumerState<IdentityPickerScreen> createState() => _IdentityPickerScreenState();
}

class _IdentityPickerScreenState extends ConsumerState<IdentityPickerScreen> {
  List<AuthUser>? _identities;
  AuthUser? _selected;
  final _pinController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identities = await ref.read(authRepositoryProvider).listLocalIdentities();
    if (!mounted) return;
    setState(() {
      _identities = identities;
      if (identities.length == 1) _selected = identities.first;
    });
  }

  void _addDigit(String digit) {
    if (_submitting) return;
    setState(() {
      _pinController.text += digit;
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  void _removeDigit() {
    if (_submitting || _pinController.text.isEmpty) return;
    setState(() {
      _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  Future<void> _continueAs(AuthUser identity, {String? pin}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    // switchLocalUser changes the local session immediately after validating
    // the PIN. If cloud authorization then fails, leaving that local session
    // behind would make the UI's sessionProvider and AuthRepository disagree
    // about who is signed in. Treat the whole employee switch as one
    // security boundary: either cloud authorization becomes ready, or the
    // partially switched employee session is cleared.
    var employeeSessionChanged = false;
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .switchLocalUser(userId: identity.id, pin: pin);
      var employeeRow = await (ref.read(databaseProvider).select(
        ref.read(databaseProvider).employees,
      )..where((e) => e.authUserId.equals(identity.id)))
          .getSingleOrNull();
      employeeRow ??= await (ref.read(databaseProvider).select(
        ref.read(databaseProvider).employees,
      )..where((e) => e.cloudUserId.equals(identity.id)))
          .getSingleOrNull();
      final isEmployeeIdentity =
          employeeRow != null || identity.role != AuthRole.owner;
      employeeSessionChanged = isEmployeeIdentity;

      if (isEmployeeIdentity) {
        final accessToken = await ref.read(apiClientProvider).restoreServerSessionForUser(
              userId: identity.id,
              supabaseUrl: SupabaseConfig.url,
              publishableKey: SupabaseConfig.publishableKey,
            );
        if (accessToken == null) {
          throw const BusinessRuleFailure(
            'This employee needs to sign in with their Fulus email and password first.',
          );
        }

        final connection = ref.read(fulusConnectionStateProvider);
        connection.markSessionAuthenticated();
        await connection.refresh();
        final active = connection.membershipContext?.memberships
                .where((membership) => membership.status == 'active')
                .toList(growable: false) ??
            const [];
        if (active.length != 1) {
          throw const BusinessRuleFailure(
            'This employee no longer has one active Fulus business on this device.',
          );
        }
        await connection.selectBusiness(active.single.businessId);
        final claim = await ref
            .read(fulusStaffAccessApiProvider)
            .getMyAccess(businessId: active.single.businessId);
        if (claim.userId != identity.id) {
          throw const AuthFailure.forbidden();
        }
        await ref.read(employeeCloudSessionCoordinatorProvider).activateExisting(
              claim: claim,
            );
      }

      if (!mounted) return;
      ref.read(sessionProvider.notifier).state =
          ref.read(authRepositoryProvider).currentUser ?? user;
      context.closeScreenOr('/');
    } on Failure catch (f) {
      await _handleFailedSwitch(employeeSessionChanged);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _switchErrorMessage(f);
        _pinController.clear();
      });
    } catch (error) {
      await _handleFailedSwitch(employeeSessionChanged);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = syncUserMessage(error);
        _pinController.clear();
      });
    }
  }

  String _switchErrorMessage(Failure failure) {
    if (failure is NetworkFailure) {
      return 'We couldn’t connect right now. Please try again.';
    }
    if (failure is BusinessRuleFailure ||
        failure is AuthFailure) {
      return 'We couldn’t switch to that employee. Please try again.';
    }
    return 'We couldn’t switch employees. Please try again.';
  }

  Future<void> _handleFailedSwitch(bool employeeSessionChanged) async {
    if (!employeeSessionChanged) return;

    // The employee identity has already been made locally active, so do not
    // leave a half-authorized identity behind. Clearing both local and cloud
    // session state is safer than allowing the previous employee's cloud
    // token to remain paired with a failed target switch. The next attempt
    // can use the normal Fulus email/password login path.
    await ref.read(apiClientProvider).clearActiveCloudSession();
    ref.read(fulusConnectionStateProvider).disconnect();
    await ref.read(syncServiceProvider).disable();
    await ref.read(authRepositoryProvider).logout();
    ref.read(sessionProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final identities = _identities;
    if (identities == null) {
      return const FulusScreen(body: FulusLoadingIndicator());
    }
    final selected = _selected;
    if (selected == null) return _buildNameList(context, identities);
    if (!selected.hasLoginPin) return _buildContinueOnly(context, selected, showBack: identities.length > 1);
    return _buildPinEntry(context, selected, showBack: identities.length > 1);
  }

  Widget _buildNameList(BuildContext context, List<AuthUser> identities) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Who's this?",
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Choose your Fulus profile to continue.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                for (final identity in identities) ...[
                  _IdentityRow(identity: identity, onTap: () => setState(() => _selected = identity)),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueOnly(BuildContext context, AuthUser identity, {required bool showBack}) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBack) _buildBackButton(),
                _buildAvatar(context, identity),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Welcome back, ${identity.fullName}',
                  textAlign: TextAlign.center,
                  style: AppTypography.heading.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Ready to run your business?',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: 'Continue',
                  loading: _submitting,
                  onPressed: _submitting ? null : () => _continueAs(identity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(BuildContext context, AuthUser identity, {required bool showBack}) {
    final pinLength = _pinController.text.length;
    return FulusScreen(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBack) Align(alignment: Alignment.centerLeft, child: _buildBackButton()),
                    _buildAvatar(context, identity),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.heading.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      identity.fullName,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _PinIndicator(length: pinLength, error: _error != null),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(color: AppColors.errorOf(context)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FulusPinKeypad(
                      onDigit: _addDigit,
                      onBackspace: _removeDigit,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: 190,
                      child: FulusButton(
                        label: 'Continue',
                        loading: _submitting,
                        onPressed: _submitting ? null : () => _continueAs(identity, pin: _pinController.text.trim()),
                      ),
                    ),
                    if (constraints.maxHeight > 760) const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return FulusIconButton(
      icon: FulusIcons.arrowBack,
      tooltip: 'Back',
      onPressed: () => setState(() {
        _selected = null;
        _pinController.clear();
        _error = null;
      }),
    );
  }

  Widget _buildAvatar(BuildContext context, AuthUser identity) {
    final initial = identity.fullName.trim().isEmpty ? '?' : identity.fullName.trim()[0].toUpperCase();
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.selectedTintOf(context),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppTypography.display.copyWith(
          color: AppColors.primaryOf(context),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PinIndicator extends StatelessWidget {
  const _PinIndicator({required this.length, required this.error});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final visibleCount = length.clamp(4, 8);
    final primary = AppColors.primaryOf(context);
    final border = error ? AppColors.errorOf(context) : AppColors.borderOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleCount; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? primary : Colors.transparent,
              border: Border.all(color: i < length ? primary : border, width: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.identity, required this.onTap});

  final AuthUser identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = identity.fullName.trim().isEmpty ? '?' : identity.fullName.trim()[0].toUpperCase();
    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.selectedTintOf(context), shape: BoxShape.circle),
            child: Text(
              initial,
              style: AppTypography.body.copyWith(
                color: AppColors.primaryOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              identity.fullName,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(FulusIcons.chevronRight, color: AppColors.textSecondaryOf(context), size: AppIconSize.compact),
        ],
      ),
    );
  }
}
