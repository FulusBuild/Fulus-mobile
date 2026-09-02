import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider, sessionPermissionsProvider, sessionProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/transaction_tile.dart' show moneyTransactionIcon;

/// Feature (Receipt History): "browse past sales, reprint any of them"
/// — a dedicated, sales-only counterpart to Money History
/// (`money_history_screen.dart`), which mixes every transaction type
/// together with its own type/category chips. There is no separate
/// Receipt table to query (`ReceiptRepositoryImpl.buildReceiptData`
/// regenerates a receipt fresh from its `Sale` row every time — see
/// that method's own doc comment) and this screen doesn't build a
/// second reprint UI either: tapping a row opens the existing
/// [TransactionDetailScreen] via the same `moneyTransactionDetail`
/// route every other list in this feature already uses, and that
/// screen's own "Print receipt" button (already wired to
/// `ReceiptPreviewSheet.show` — the exact code path checkout's own
/// post-sale screen uses) is what actually satisfies "open a receipt →
/// print/reprint." Nothing here duplicates either of those.
///
/// All-time by design, not scoped to Money's shared period selector
/// (`moneyPeriodProvider`) — a "browse every past sale, bank-statement
/// style" screen shouldn't quietly hide last month's receipts just
/// because Money's own period chip happens to be set to "Today"
/// elsewhere. [_historyStart] mirrors `RealMoneyRepositoryImpl._epoch`'s
/// own "wide enough to include everything a real business could have
/// recorded" reasoning — that field is private to its own file, so this
/// is a second, independent constant with the same value rather than a
/// shared import.
class ReceiptHistoryScreen extends ConsumerStatefulWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  ConsumerState<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends ConsumerState<ReceiptHistoryScreen> {
  static final DateTime _historyStart = DateTime(2000, 1, 1);

  String _searchQuery = '';
  String _builtForQuery = '';
  Timer? _debounce;
  late Future<List<MoneyTransaction>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Employee data isolation: the same `currentAuthUserId`/
  /// `canViewAllSales` computation every other Money screen uses —
  /// copied verbatim from `money_screen.dart`'s own `_load()`, per the
  /// brief's own instruction to reuse that exact pattern rather than
  /// re-deriving it — so an employee without
  /// `Permission.viewDashboardStats` sees only their own past sales
  /// here, exactly as Cash Flow and Money History already scope theirs.
  void _load() {
    final repo = ref.read(moneyRepositoryProvider);
    _builtForQuery = _searchQuery;
    final user = ref.read(sessionProvider);
    final currentAuthUserId = user?.id ?? '';
    final permissions = ref.read(sessionPermissionsProvider).value ?? const {};
    final canViewAllSales = user?.role == AuthRole.owner || permissions.contains(Permission.viewDashboardStats);
    final period = ReportPeriod(kind: ReportPeriodKind.custom, start: _historyStart, end: DateTime.now());
    _future = repo.getTransactions(
      period,
      currentAuthUserId: currentAuthUserId,
      canViewAllSales: canViewAllSales,
      typeFilter: MoneyTransactionType.saleIncome,
      searchQuery: _searchQuery,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same re-trigger-on-external-change pattern as every other Money
    // screen's own dataRefreshSignalProvider listener (see
    // money_screen.dart's identical block) — a sale recorded elsewhere
    // (checkout, a refund) shows up here without a manual pull-to-
    // refresh.
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) {
        setState(_load);
      }
    });
    if (_builtForQuery != _searchQuery) {
      _load();
    }
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Receipt history',
      applyPadding: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: FulusSearchField(hintText: 'Search receipts', onChanged: _onSearchChanged),
          ),
          Expanded(
            child: FutureBuilder<List<MoneyTransaction>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FulusErrorState(
                    message: "Couldn't load your receipts.",
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
                      icon: Icons.receipt_outlined,
                      headline: 'No receipts found.',
                      body: _searchQuery.isNotEmpty
                          ? 'Try a different search term.'
                          : 'Sales you record will show up here, ready to reprint any time.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: _GroupedReceiptList(items: items, currencySymbol: currencySymbol),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Same "group under a day header, most recent day first" shape as
/// Money History's own `_GroupedTransactionList` — bank-app style, per
/// the request — but each row is [_ReceiptRow] rather than
/// [MoneyTransactionTile]: a receipt row's identifying details
/// (customer, receipt/invoice number) aren't part of that shared
/// tile's own subtitle, which only ever shows date/time/payment method
/// (it's shared across every transaction type in Money, not
/// receipt-specific — see its own doc comment).
class _GroupedReceiptList extends StatelessWidget {
  const _GroupedReceiptList({required this.items, required this.currencySymbol});

  final List<MoneyTransaction> items;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final t in items) {
      groups.putIfAbsent(formatRelativeDay(t.dateTime), () => []).add(t);
    }
    final dayKeys = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      itemCount: dayKeys.length,
      itemBuilder: (context, index) {
        final dayKey = dayKeys[index];
        final dayItems = groups[dayKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
              child: Text(
                dayKey,
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
                  for (var i = 0; i < dayItems.length; i++) ...[
                    if (i > 0) const FulusListDivider(),
                    _ReceiptRow(
                      transaction: dayItems[i],
                      currencySymbol: currencySymbol,
                      onTap: () => context.pushNamed(
                        'moneyTransactionDetail',
                        pathParameters: {'id': dayItems[i].id},
                        extra: dayItems[i],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        );
      },
    );
  }
}

/// One past sale — enough to identify it at a glance: the time
/// (grouped under a day header, so the date itself isn't repeated per
/// row — same convention `MoneyTransactionTile.showDate: false` uses
/// elsewhere), the receipt/invoice number (via [MoneyTransaction.title],
/// already formatted as "Sale — INV-2041", falling back to plain
/// "Sale" when a sale has none), and the customer if one was attached.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.transaction, required this.currencySymbol, this.onTap});

  final MoneyTransaction transaction;
  final String currencySymbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final subtitleParts = <String>[
      formatTime(t.dateTime),
      if (t.counterpartyName != null) t.counterpartyName!,
      if (t.subtitle != null) t.subtitle!,
    ];

    return FulusListRow(
      leading: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
        child: Center(
          child: Icon(
            moneyTransactionIcon(t),
            size: AppIconSize.compact,
            color: AppColors.primaryOf(context),
          ),
        ),
      ),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      // Plain, unsigned — unlike MoneyTransactionTile's `signedAmount,
      // showSign: true` (built for a feed that mixes inflows/outflows),
      // every row here is a sale, so a "+" would only ever repeat the
      // same fact every other row already states.
      trailing: Text(
        formatMoney(t.amount, symbol: currencySymbol),
        style: AppTypography.body.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
      onTap: onTap,
    );
  }
}
