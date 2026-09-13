import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';

/// The first-run setup is intentionally local-first and minimal.
class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({super.key});

  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  final _businessNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  Failure? _failure;

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _createBusiness() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });

    try {
      final authUser = ref.read(sessionProvider);
      if (authUser == null) {
        throw const AuthFailure(message: 'Your session has expired. Please sign in again.');
      }
      await ref.read(onboardingRepositoryProvider).createBusiness(
        ownerUserId: authUser.id,
        businessName: _businessNameController.text.trim(),
        category: BusinessCategory.retailShop,
        currencySymbol: '₦',
      );
      if (!mounted) return;
      context.go('/');
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = UnknownFailure(message: error.toString());
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) exitScreen(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        appBar: AppBar(title: const Text('Create your business')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xxxl),
              children: [
                Text('Start selling in minutes.', style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Give your business a name. You can change the rest later in Settings.',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TextFormField(
                  controller: _businessNameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _createBusiness(),
                  decoration: const InputDecoration(labelText: 'Business name', hintText: 'e.g. Muhammed Mini Mart'),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Enter your business name';
                    if (name.length < 2) return 'Use at least 2 characters';
                    return null;
                  },
                ),
                if (_failure != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AuthErrorBanner(failure: _failure!),
                ],
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  child: FulusButton(
                    label: _saving ? 'Creating…' : 'Create business',
                    onPressed: _saving ? null : _createBusiness,
                    isLoading: _saving,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Works offline. Cloud sync can be connected later.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(color: AppColors.mutedOf(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
