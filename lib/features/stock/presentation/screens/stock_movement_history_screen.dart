import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/stock_movement_tile.dart';

/// "What recently changed?" in full — the Stock overview's own Recent
/// Activity preview caps at 3; this is that same feed, unfiltered,
/// reachable via its "See all." [productId] narrows it to one product's
/// history when opened from [ProductDetailScreen] rather than a bare
/// re-implementation of that screen's own history section — though in
/// practice ProductDetailScreen renders its own inline (no navigation
/// needed there, the whole point of a detail screen already being
/// scrolled to), so [productId] mainly exists so this screen's contract
/// supports that case if a future screen wants to link to it directly.
class StockMovementHistoryScreen extends ConsumerWidget {
  const StockMovementHistoryScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(currentLocationIdProvider);

    return FulusScreen(
      title: 'Stock activity',
      applyPadding: false,
      body: locationAsync.when(
        loading: () => const FulusLoadingIndicator(),
        error: (e, _) => FulusErrorState(
          message: "Couldn't load activity.",
          onRetry: () => ref.invalidate(currentLocationIdProvider),
        ),
        data: (locationId) => _HistoryList(locationId: locationId, productId: productId),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.locationId, this.productId});

  final String locationId;
  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(stockMovementsProvider(locationId));
    final productsAsync = ref.watch(productsWithStockProvider(locationId));

    return movementsAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()],
      ),
      error: (e, _) => FulusErrorState(
        message: "Couldn't load activity.",
        reassurance: 'Nothing in your stock was changed — this is only about viewing the history.',
        onRetry: () => ref.invalidate(stockMovementsProvider(locationId)),
      ),
      data: (movements) {
        final filtered =
            productId == null ? movements : movements.where((m) => m.productLocalId == productId).toList();

        if (filtered.isEmpty) {
          return const FulusEmptyState(
            headline: 'No activity yet.',
            body: 'Stock you record will show up here.',
            icon: FulusIcons.history,
          );
        }

        final productById = {
          for (final p in productsAsync.asData?.value ?? const []) p.product.localId: p.product,
        };

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const FulusListDivider(),
          itemBuilder: (context, index) {
            final movement = filtered[index];
            return StockMovementTile(
              movement: movement,
              showProductName: productId == null,
              product: productById[movement.productLocalId],
            );
          },
        );
      },
    );
  }
}
