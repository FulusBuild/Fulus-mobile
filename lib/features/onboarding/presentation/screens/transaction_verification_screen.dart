import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/product.dart';
import '../../../../domain/entities/sale.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import 'completion_screen.dart';

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// Walkthrough Phase 10 — "one sale flows through your business
/// records." Every number here is read from the real, already-
/// persisted sale and product, not recomputed or faked: `Sale.items`
/// for what was sold, `ProductWithStock.currentStock` for the after
/// figure, `before = after + sold` (arithmetic on two real numbers, not
/// a third invented one). Inventory and Sales are direct — Cash/
/// Finance and Reports deliberately link out to the real screens
/// rather than re-deriving their numbers here, which would risk a
/// second, possibly-drifting copy of logic those screens already own.
class TransactionVerificationScreen extends ConsumerStatefulWidget {
  const TransactionVerificationScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<TransactionVerificationScreen> createState() =>
      _TransactionVerificationScreenState();
}

class _TransactionVerificationScreenState extends ConsumerState<TransactionVerificationScreen> {
  late Future<Sale?> _saleFuture = ref.read(saleRepositoryProvider).getSaleByLocalId(widget.saleId);

  void _retry() {
    setState(() {
      _saleFuture = ref.read(saleRepositoryProvider).getSaleByLocalId(widget.saleId);
    });
  }

  Future<void> _continue() async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.advanceWalkthroughTo(OnboardingStep.completion);
    if (!mounted) return;
    ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.completion;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CompletionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'What changed',
      body: FutureBuilder<Sale?>(
        future: _saleFuture,
        builder: (context, saleSnapshot) {
          if (saleSnapshot.connectionState != ConnectionState.done) {
            return const FulusLoadingIndicator();
          }
          if (saleSnapshot.hasError) {
            return _VerificationErrorView(onRetry: _retry, onContinue: _continue);
          }
          final sale = saleSnapshot.data;
          if (sale == null) {
            // The sale this screen was told to look up doesn't exist —
            // an honest empty state, not a crash or a fabricated one.
            return _MissingSaleView(onContinue: _continue);
          }
          return _VerificationBody(sale: sale, onContinue: _continue);
        },
      ),
    );
  }
}

class _VerificationErrorView extends StatelessWidget {
  const _VerificationErrorView({required this.onRetry, required this.onContinue});

  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "We couldn't load what changed from your sale. It's already saved — this is just "
            "this screen having trouble reading it back.",
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusButton(label: 'Try again', onPressed: onRetry),
          const SizedBox(height: AppSpacing.sm),
          FulusButton(
            label: 'Skip this',
            variant: FulusButtonVariant.text,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _MissingSaleView extends StatelessWidget {
  const _MissingSaleView({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "We couldn't find that sale to show you what changed, but it's already recorded — "
            'you can find it in Money and Sales any time.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _VerificationBody extends ConsumerWidget {
  const _VerificationBody({required this.sale, required this.onContinue});

  final Sale sale;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';
    final soldItem = _firstWhereOrNull(sale.items, (item) => item.productLocalId != null);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'One sale, four places it shows up.',
            style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (soldItem != null)
            _InventorySection(productLocalId: soldItem.productLocalId!, sold: soldItem.quantity)
          else
            _VerificationCard(
              title: 'Inventory',
              body: "This was a quick sale, not tied to a specific product in your catalog — "
                  'so there\'s no stock count to show changing.',
            ),
          const SizedBox(height: AppSpacing.md),
          _VerificationCard(
            title: 'Sales',
            body: '${soldItem?.description ?? 'Your sale'} · '
                '${formatMoney(sale.total, symbol: currencySymbol)}',
            action: ('View sale history', () => context.goNamed('moneyHistory')),
          ),
          const SizedBox(height: AppSpacing.md),
          _VerificationCard(
            title: 'Cash / Finance',
            body: sale.paymentMethod != null
                ? 'Paid by ${sale.paymentMethod} — recorded in your Money history.'
                : 'Recorded in your Money history.',
            action: ('View in Money', () => context.goNamed('moneyHistory')),
          ),
          const SizedBox(height: AppSpacing.md),
          _VerificationCard(
            title: 'Reports',
            body: "Reflected in your Sales report as soon as you look.",
            action: ('View Reports', () => context.goNamed('moreReports')),
          ),
          const SizedBox(height: AppSpacing.xl),
          FulusButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _InventorySection extends ConsumerWidget {
  const _InventorySection({required this.productLocalId, required this.sold});

  final String productLocalId;
  final int sold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.read(activeLocationIdProvider.future),
      builder: (context, locationSnapshot) {
        if (locationSnapshot.connectionState != ConnectionState.done) {
          return const _VerificationCard(title: 'Inventory', body: 'Loading…');
        }
        final locationId = locationSnapshot.data;
        if (locationSnapshot.hasError || locationId == null) {
          return _unavailableCard(sold);
        }
        return StreamBuilder<List<ProductWithStock>>(
          stream: ref.read(productRepositoryProvider).watchProducts(locationId: locationId),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _unavailableCard(sold);
            if (!snapshot.hasData) {
              return const _VerificationCard(title: 'Inventory', body: 'Loading…');
            }
            final match = _firstWhereOrNull(
              snapshot.data!,
              (p) => p.product.localId == productLocalId,
            );
            if (match == null) {
              return _VerificationCard(
                title: 'Inventory',
                body: 'Sold: $sold — the product itself has since been removed from your catalog.',
              );
            }
            final after = match.currentStock;
            final before = after + sold;
            return _VerificationCard(
              title: 'Inventory',
              body: '${match.product.name} — before: $before, sold: $sold, after: $after.',
              action: (
                'View in Stock',
                () => context.pushNamed(
                  'stockProductDetail',
                  pathParameters: {'productId': productLocalId},
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _unavailableCard(int sold) {
    return _VerificationCard(
      title: 'Inventory',
      body: "Sold: $sold — couldn't load your current stock count right now, but it's "
          'accurate in Stock.',
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.label.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FulusButton(
              label: action!.$1,
              variant: FulusButtonVariant.text,
              onPressed: action!.$2,
            ),
          ],
        ],
      ),
    );
  }
}
