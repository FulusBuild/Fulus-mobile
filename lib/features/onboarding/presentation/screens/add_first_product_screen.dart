import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../stock/presentation/screens/add_edit_product_screen.dart';
import '../widgets/onboarding_error_banner.dart';

/// Walkthrough Phase 4. Opens the real [AddEditProductScreen] rather
/// than a tutorial copy of the form — it pops with no return value on
/// save (same as every other caller of it, per router.dart), so success
/// here is detected the same way any reactive caller of `watchProducts`
/// would notice a new product: check the catalog after returning, not
/// the pop itself. Since this step is only reachable right after a
/// brand-new business is created, an empty catalog before this screen
/// is a given, not an assumption — any non-empty result after returning
/// means the user genuinely saved one.
///
/// Reached via a direct [Navigator.push], not `context.pushNamed`'s
/// named-route form — deliberately, not out of habit: this screen
/// itself is shown by `_ShellGate` (router.dart) OUTSIDE the normal
/// `StatefulShellRoute` branch tree (a walkthrough overlay, not
/// `navigationShell`'s own content), the same situation
/// `OwnerSetupScreen`/`GetStartedScreen`/`RestoreProgressScreen` and the
/// SaleSuccessScreen -> TransactionVerificationScreen -> CompletionScreen
/// chain are already in — and every one of those already reaches its
/// next screen the same direct way rather than through a named route
/// nested inside a branch that may never have been built in this
/// session. `stockAddProduct` names a route two levels inside the Stock
/// branch specifically; pushing it by name from here would depend on
/// go_router resolving and activating that branch's own Navigator on
/// demand from outside its normal tree, which nothing else reached from
/// this same overlay position relies on either. [AddEditProductScreen]
/// itself doesn't need to sit inside that branch to work correctly —
/// it's a self-contained form over repository providers, not something
/// that reads its position in the tree — so pushing it directly sidesteps
/// the question entirely rather than depending on the answer being yes.
class AddFirstProductScreen extends ConsumerStatefulWidget {
  const AddFirstProductScreen({super.key});

  @override
  ConsumerState<AddFirstProductScreen> createState() => _AddFirstProductScreenState();
}

class _AddFirstProductScreenState extends ConsumerState<AddFirstProductScreen> {
  bool _checking = false;
  String? _errorMessage;

  Future<void> _advanceTo(OnboardingStep step) async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.advanceWalkthroughTo(step);
    if (!mounted) return;
    ref.read(walkthroughStepProvider.notifier).state = step;
  }

  Future<void> _openProductForm() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AddEditProductScreen(pushedImperatively: true)),
    );
    if (!mounted) return;
    setState(() {
      _checking = true;
      _errorMessage = null;
    });
    try {
      final locationId = await ref.read(activeLocationIdProvider.future);
      final products =
          await ref.read(productRepositoryProvider).watchProducts(locationId: locationId).first;
      if (!mounted) return;
      if (products.isNotEmpty) {
        await _advanceTo(OnboardingStep.navigationIntro);
      }
      // Still empty: the user backed out without saving. Stay on this
      // screen rather than falsely advancing — they can try again or
      // use the skip option below.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Couldn't confirm whether your product saved. Check your Stock "
            'list before adding another, just in case.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _skip() async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.skipWalkthroughStep(OnboardingStep.firstProduct);
    await _advanceTo(OnboardingStep.navigationIntro);
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add your first product',
                  style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Products are what you'll sell. Let's add your first one — it'll go "
                  'straight into your real inventory.',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  OnboardingErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.md),
                ],
                FulusActionTile(
                  icon: FulusIcons.add,
                  title: 'Add a product',
                  subtitle: 'Create your first real inventory item.',
                  trailing: _checking ? const FulusLoadingIndicator() : null,
                  onTap: _checking ? null : _openProductForm,
                ),
                const SizedBox(height: AppSpacing.md),
                FulusActionTile(
                  icon: FulusIcons.stock,
                  title: "I'll add products later",
                  subtitle: 'You can build your catalog from Stock anytime.',
                  onTap: _checking ? null : _skip,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
