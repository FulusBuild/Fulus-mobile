import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/stock_movement_tile.dart';

/// "What recently changed?" in full — the Stock overview's own Recent
/// Activity preview caps at 3; this is that same feed, unfiltered,
/// reachable via its "See all." [productId] narrows it to one product's
/// history when opened from [ProductDetailScreen].
class StockMovementHistoryScreen extends ConsumerWidget {
  const StockMovementHistoryScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(currentLocationIdProvider);

    return FulusScreen(
      title: productId == null ? 'Stock activity' : 'Product activity',
      subtitle: productId == null
          ? 'Recent changes to stock across your business'
          : 'Recent stock changes for this product',
      applyPadding: false,
      actions: [
        FulusIconButton(
          icon: FulusIcons.sync,
          tooltip: 'Refresh activity',
          onPressed: () {
            final locationId = locationAsync.asData?.value;
            if (locationId != null) {
              ref.invalidate(stockMovementsProvider(locationId));
              ref.invalidate(productsWithStockProvider(locationId));
            } else {
              ref.invalidate(currentLocationIdProvider);
            }
          },
        ),
      ],
      body: locationAsync.when(
        loading: () => const FulusLoadingIndicator(),
        error: (e, _) => FulusErrorState(
          message: "Couldn't load activity.",
          reassurance: 'Your stock records were not changed.',
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
        final filtered = productId == null
            ? movements
            : movements.where((m) => m.productLocalId == productId).toList();

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
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xxl),
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
