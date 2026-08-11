import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';

/// Volume 8's shared period selector — "Today / This Week / This Month
/// / Custom" — reused by the Cash Flow screen and Money History so
/// both stay on the exact same selection ([moneyPeriodKindProvider]/
/// [customMoneyRangeProvider] are app-level, not screen-local state).
class MoneyPeriodFilterBar extends ConsumerWidget {
  const MoneyPeriodFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(moneyPeriodKindProvider);
    final customRange = ref.watch(customMoneyRangeProvider);

    String labelFor(ReportPeriodKind k) {
      switch (k) {
        case ReportPeriodKind.today:
          return 'Today';
        case ReportPeriodKind.thisWeek:
          return 'This week';
        case ReportPeriodKind.thisMonth:
          return 'This month';
        case ReportPeriodKind.custom:
          if (customRange == null) return 'Custom';
          return '${formatRelativeDay(customRange.start)} – ${formatRelativeDay(customRange.end)}';
      }
    }

    Future<void> pickCustomRange() async {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      );
      if (picked != null) {
        ref.read(customMoneyRangeProvider.notifier).state = picked;
        ref.read(moneyPeriodKindProvider.notifier).state = ReportPeriodKind.custom;
      }
    }

    return FulusChipRow(children: [
      for (final k in const [ReportPeriodKind.today, ReportPeriodKind.thisWeek, ReportPeriodKind.thisMonth])
        FulusChip(
          label: labelFor(k),
          selected: kind == k,
          onTap: () => ref.read(moneyPeriodKindProvider.notifier).state = k,
        ),
      FulusChip(
        label: labelFor(ReportPeriodKind.custom),
        selected: kind == ReportPeriodKind.custom,
        onTap: pickCustomRange,
      ),
    ]);
  }
}
