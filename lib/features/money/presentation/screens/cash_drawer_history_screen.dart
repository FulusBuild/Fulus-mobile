import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/cash_drawer_shift.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';

/// Persisted close facts for this location. The historic sales breakdown is
/// intentionally not reconstructed here because the shift row does not store
/// it; drawer-linked cash supplier payments are reflected in the close facts.
class CashDrawerHistoryScreen extends ConsumerWidget {
  const CashDrawerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final location = ref.watch(activeLocationIdProvider);

    return FulusScreen(
      title: 'Cash drawer history',
      body: location.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FulusErrorState(
          message: "Couldn't load this location's drawer history.",
          onRetry: () => ref.invalidate(activeLocationIdProvider),
        ),
        data: (locationId) => StreamBuilder<List<CashDrawerShift>>(
          stream: ref
              .watch(cashDrawerShiftRepositoryProvider)
              .watchShiftHistory(locationId: locationId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return FulusErrorState(
                message: "Couldn't load cash drawer history.",
                onRetry: () =>
                    ref.invalidate(cashDrawerShiftRepositoryProvider),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final shifts = snapshot.data!;
            if (shifts.isEmpty) {
              return const FulusEmptyState(
                icon: Icons.point_of_sale_outlined,
                headline: 'No drawer sessions yet',
                body:
                    'Closed drawer sessions will appear here for this location.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              itemCount: shifts.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _ShiftCard(
                shift: shifts[index],
                currencySymbol: currencySymbol,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.shift, required this.currencySymbol});

  final CashDrawerShift shift;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final closed = shift.closedAt != null;
    final expected = shift.closingCash != null && shift.cashDifference != null
        ? shift.closingCash! - shift.cashDifference!
        : null;

    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatRelativeDay(shift.openedAt)} · ${formatTime(shift.openedAt)}',
            style: AppTypography.subheading.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            closed && shift.closedAt != null
                ? 'Closed ${formatTime(shift.closedAt!)}'
                : 'Still open',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ShiftValue(
            label: 'Opening float',
            value: shift.openingCash,
            currencySymbol: currencySymbol,
          ),
          if (expected != null)
            _ShiftValue(
              label: 'Expected cash',
              value: expected,
              currencySymbol: currencySymbol,
            ),
          if (shift.closingCash != null)
            _ShiftValue(
              label: 'Counted cash',
              value: shift.closingCash!,
              currencySymbol: currencySymbol,
            ),
          if (shift.cashDifference != null)
            _ShiftValue(
              label: shift.cashDifference == 0
                  ? 'Difference'
                  : shift.cashDifference! > 0
                  ? 'Over'
                  : 'Short',
              value: shift.cashDifference!.abs(),
              currencySymbol: currencySymbol,
            ),
          if (shift.closingNote?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              shift.closingNote!,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShiftValue extends StatelessWidget {
  const _ShiftValue({
    required this.label,
    required this.value,
    required this.currencySymbol,
  });

  final String label;
  final int value;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              formatMoney(value, symbol: currencySymbol),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
