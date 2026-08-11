import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/export/export_service.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/mock_money_repository.dart';
import '../../domain/money_history_filter.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/transaction_tile.dart';

/// Volume 8's "the actual list of transactions" every Cash Flow row
/// and card is tappable through to — search, the shared period
/// selector, a type/category filter, and an Export action (real —
/// `ExportService`, Volume 10's own CSV/PDF/Share Sheet mechanism).
class MoneyHistoryScreen extends ConsumerStatefulWidget {
  const MoneyHistoryScreen({super.key});

  @override
  ConsumerState<MoneyHistoryScreen> createState() => _MoneyHistoryScreenState();
}

class _MoneyHistoryScreenState extends ConsumerState<MoneyHistoryScreen> {
  bool _initializedFromExtra = false;
  MoneyTransactionType? _typeFilter;
  String? _categoryFilter;
  String _searchQuery = '';
  Timer? _debounce;

  ReportPeriod? _builtForPeriod;
  MoneyTransactionType? _builtForType;
  String? _builtForCategory;
  String _builtForQuery = '';
  late Future<List<MoneyTransaction>> _future;

  bool _needsReload(ReportPeriod period) =>
      _builtForPeriod != period ||
      _builtForType != _typeFilter ||
      _builtForCategory != _categoryFilter ||
      _builtForQuery != _searchQuery;

  void _load(ReportPeriod period) {
    final repo = ref.read(moneyRepositoryProvider);
    _builtForPeriod = period;
    _builtForType = _typeFilter;
    _builtForCategory = _categoryFilter;
    _builtForQuery = _searchQuery;
    _future = repo.getTransactions(
      period,
      typeFilter: _typeFilter,
      category: _categoryFilter,
      searchQuery: _searchQuery,
    );
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await _future;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  void _selectType(MoneyTransactionType? type) {
    setState(() {
      _typeFilter = type;
      _categoryFilter = null;
    });
  }

  void _toggleSimulatedError() {
    final repo = ref.read(moneyRepositoryProvider);
    if (repo is MockMoneyRepository) {
      repo.debugSimulateFailure = !repo.debugSimulateFailure;
    }
    _refresh();
  }

  Future<void> _export(List<MoneyTransaction> items, String currencySymbol, ReportPeriod period) async {
    if (items.isEmpty) {
      showFulusSnackbar(context, message: 'Nothing to export for this period.');
      return;
    }
    final format = await showFulusBottomSheet<ExportFormat>(
      context: context,
      title: 'Export transactions',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('CSV'),
            subtitle: const Text('Open in a spreadsheet'),
            onTap: () => Navigator.of(sheetContext).pop(ExportFormat.csv),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Share a printable summary'),
            onTap: () => Navigator.of(sheetContext).pop(ExportFormat.pdf),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    try {
      await ref.read(exportServiceProvider).export(
            format: format,
            fileName: 'money-history-${DateTime.now().millisecondsSinceEpoch}',
            title: 'Money history',
            subtitle: '${formatRelativeDay(period.start)} – ${formatRelativeDay(period.end)}',
            headers: const ['Date', 'Time', 'Type', 'Description', 'Payment method', 'Amount'],
            rows: [
              for (final t in items)
                [
                  formatRelativeDay(t.dateTime),
                  formatTime(t.dateTime),
                  _typeLabel(t.type),
                  t.title,
                  t.paymentMethod ?? '—',
                  formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true),
                ],
            ],
          );
    } catch (_) {
      if (mounted) showFulusSnackbar(context, message: "Couldn't export right now. Please try again.");
    }
  }

  static String _typeLabel(MoneyTransactionType type) {
    switch (type) {
      case MoneyTransactionType.saleIncome:
        return 'Sale';
      case MoneyTransactionType.manualIncome:
        return 'Income';
      case MoneyTransactionType.customerRepayment:
        return 'Repayment';
      case MoneyTransactionType.expense:
        return 'Expense';
      case MoneyTransactionType.supplierPayment:
        return 'Supplier payment';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initializedFromExtra) {
      _initializedFromExtra = true;
      final extra = GoRouterState.of(context).extra;
      if (extra is MoneyHistoryFilterRequest) {
        _typeFilter = extra.type;
        _categoryFilter = extra.category;
      }
    }
    final period = ref.watch(moneyPeriodProvider);
    if (_needsReload(period)) {
      _load(period);
    }
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return FulusScreen(
      title: 'Money history',
      applyPadding: false,
      actions: [
        if (kDebugMode)
          FulusIconButton(icon: Icons.bug_report_outlined, tooltip: 'Simulate error (debug)', onPressed: _toggleSimulatedError),
        FulusIconButton(
          icon: Icons.ios_share,
          tooltip: 'Export',
          onPressed: () async {
            final items = await _future;
            await _export(items, currencySymbol, period);
          },
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: FulusSearchField(hintText: 'Search transactions', onChanged: _onSearchChanged),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: const MoneyPeriodFilterBar(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FulusChipRow(children: [
              FulusChip(label: 'All', selected: _typeFilter == null, onTap: () => _selectType(null)),
              FulusChip(
                label: 'Sales',
                selected: _typeFilter == MoneyTransactionType.saleIncome,
                onTap: () => _selectType(MoneyTransactionType.saleIncome),
              ),
              FulusChip(
                label: 'Other income',
                selected: _typeFilter == MoneyTransactionType.manualIncome,
                onTap: () => _selectType(MoneyTransactionType.manualIncome),
              ),
              FulusChip(
                label: 'Repayments',
                selected: _typeFilter == MoneyTransactionType.customerRepayment,
                onTap: () => _selectType(MoneyTransactionType.customerRepayment),
              ),
              FulusChip(
                label: 'Expenses',
                selected: _typeFilter == MoneyTransactionType.expense,
                onTap: () => _selectType(MoneyTransactionType.expense),
              ),
              FulusChip(
                label: 'Supplier payments',
                selected: _typeFilter == MoneyTransactionType.supplierPayment,
                onTap: () => _selectType(MoneyTransactionType.supplierPayment),
              ),
            ]),
          ),
          if (_categoryFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined, size: AppIconSize.dense, color: AppColors.textSecondaryOf(context)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Only "$_categoryFilter"',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _categoryFilter = null),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: FutureBuilder<List<MoneyTransaction>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FulusErrorState(
                    message: "Couldn't load your transactions.",
                    reassurance: 'Nothing recorded has been lost — this is only about showing the list right now.',
                    onRetry: _refresh,
                  );
                }
                if (!snapshot.hasData) {
                  return FulusDelayedSkeleton(
                    skeleton: ListView(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      children: List.generate(6, (_) => const FulusListRowSkeleton()),
                    ),
                  );
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return SingleChildScrollView(
                    child: FulusEmptyState(
                      icon: Icons.search_off,
                      headline: 'No transactions found.',
                      body: _searchQuery.isNotEmpty
                          ? 'Try a different search term or period.'
                          : 'Nothing was recorded for this period and filter.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: _GroupedTransactionList(items: items, currencySymbol: currencySymbol),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows grouped under a day header — "Today", "Yesterday", "12 Mar" —
/// so [MoneyTransactionTile.showDate] can be false and each row only
/// needs to carry its time, matching how a transaction's own detail
/// screen shows date once, not per row.
class _GroupedTransactionList extends StatelessWidget {
  const _GroupedTransactionList({required this.items, required this.currencySymbol});

  final List<MoneyTransaction> items;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final t in items) {
      groups.putIfAbsent(formatRelativeDay(t.dateTime), () => []).add(t);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
            child: Text(
              entry.key,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FulusCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const FulusListDivider(),
                  MoneyTransactionTile(
                    transaction: entry.value[i],
                    currencySymbol: currencySymbol,
                    showDate: false,
                    onTap: () => context.pushNamed(
                      'moneyTransactionDetail',
                      pathParameters: {'id': entry.value[i].id},
                      extra: entry.value[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}
