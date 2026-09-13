import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/dashboard_summary.dart';
import '../../../../domain/entities/report.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/domain/money_transaction.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider, moneyRepositoryProvider;
import '../../../money/presentation/widgets/opening_float_sheet.dart';
import '../../../money/presentation/widgets/transaction_tile.dart';

/// Redesign pass, Home (owner view): explicitly overrides Volume 4's
/// "one evolving hero element... not five widgets shown at once" —
/// product decision for this pass specifically, not a reinterpretation
/// of the Bible. Every other screen in this app keeps that restraint;
/// Home alone now shows a greeting header, the hero, a notice row, a
/// quick-action row, and a recent-activity feed together, matching the
/// agreed reference design. [DashboardEngine] itself is untouched — it
/// still only decides WHICH hero variant applies; this screen decides
/// how much else surrounds it.
///
/// Decision 13 ("an employee's Home is their own shift, full stop —
/// never the business total") is *not* overridden for a login with no
/// extra grant: everything below the hero here is still business-wide
/// data. Roles & Permissions (schemaVersion 10) replaces the old
/// "gated behind [isOwner], full stop" rule with
/// `Permission.viewDashboardStats` — an owner always has it (the usual
/// structural exemption), and now a Manager can be granted it too,
/// seeing the same notices/quick-actions/activity section an owner
/// does; a Cashier or a plain Employee login without the grant still
/// gets exactly Decision 13's single-card hero and nothing else. See
/// [canViewDashboardStats].
///
/// [currentAuthUserId] / [isOwner] / [canViewDashboardStats] are passed
/// in from wherever Stage 2's session lives (not built by this module —
/// see dashboard_repository.dart's own doc). Left as required
/// constructor params rather than read from a session provider this
/// module can't see, so this screen compiles and is testable in
/// isolation; the merge step is one line at the call site once Stage
/// 2's session provider exists.
///
/// Gap fix (was: "closing a mock day here doesn't flip this screen's
/// own hero state"): [HomeHeroState] still comes entirely from
/// [DashboardRepository] — untouched — but this screen also listens to
/// [dataRefreshSignalProvider] and re-fetches whenever it changes.
/// Opening or closing the drawer bumps that signal (see
/// `daily_closing_count_screen.dart`), so returning to this tab after
/// either action now shows the real, current state instead of whatever
/// was cached from this screen's last `initState`. Home stays on plain
/// Futures rather than converting to Riverpod providers itself — same
/// reasoning as before, now covering the notice/activity fetches too.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.currentAuthUserId,
    required this.isOwner,
    required this.canViewDashboardStats,
  });

  final String currentAuthUserId;
  final bool isOwner;

  /// Whether this session should see the business-wide sections below
  /// the hero (and the business-wide hero itself, not just this user's
  /// own shift) despite not being an Owner — Permission.viewDashboardStats,
  /// resolved by the caller (router.dart). Always effectively true for
  /// an Owner session regardless of what's passed here, since every
  /// `widget.isOwner || widget.canViewDashboardStats` check below treats
  /// the two as alternatives, not this flag alone.
  final bool canViewDashboardStats;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<HomeHeroState> _heroFuture;
  late Future<SecondaryNoticeSelection> _noticesFuture;
  late Future<List<MoneyTransaction>> _activityFuture;

  static const _reportsEngine = ReportsEngine();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(dashboardRepositoryProvider);
    final showBusinessWide = widget.isOwner || widget.canViewDashboardStats;
    _heroFuture = repo.getHeroState(currentAuthUserId: widget.currentAuthUserId, isOwner: showBusinessWide);
    _noticesFuture = repo.getSecondaryNotices(max: 3);
    _activityFuture = ref.read(moneyRepositoryProvider).getTransactions(
      _reportsEngine.resolvePeriod(ReportPeriodKind.today),
      currentAuthUserId: widget.currentAuthUserId,
      canViewAllSales: showBusinessWide,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture, _activityFuture]);
  }

  void _retryHomeData() {
    if (!mounted) return;
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) setState(_load);
    });
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const _GreetingHeader(),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<HomeHeroState>(
                future: _heroFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _HeroSkeleton();
                  }
                  if (snapshot.hasError) {
                    return FulusErrorState(
                      message: "Couldn't load today's summary.",
                      reassurance: 'Your sales are still safe on this device.',
                      onRetry: _retryHomeData,
                    );
                  }
                  if (!snapshot.hasData) {
                    return FulusEmptyState(
                      headline: 'Nothing to show yet',
                      body: 'Your sales summary will appear here when there is data to show.',
                      icon: Icons.storefront_outlined,
                    );
                  }
                  return _HeroCard(state: snapshot.data!, currencySymbol: currencySymbol);
                },
              ),
              if (widget.isOwner || widget.canViewDashboardStats) ...[
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<SecondaryNoticeSelection>(
                  future: _noticesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _NoticeSkeleton();
                    }
                    if (snapshot.hasError) {
                      return FulusErrorState(
                        message: "Couldn't load business alerts.",
                        reassurance: 'Your business data is still safe on this device.',
                        onRetry: _retryHomeData,
                      );
                    }
                    final selection = snapshot.data;
                    if (selection == null || selection.shown.isEmpty) return const SizedBox.shrink();
                    return _NoticeRow(selection: selection, currencySymbol: currencySymbol);
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                const _QuickActionRow(),
                const SizedBox(height: AppSpacing.xl),
                FulusSectionHeader(
                  title: 'Recent activity',
                  action: 'See all',
                  onActionTap: () => context.pushNamed('moneyHistory'),
                ),
                FutureBuilder<List<MoneyTransaction>>(
                  future: _activityFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]);
                    }
                    if (snapshot.hasError) {
                      return FulusErrorState(
                        message: "Couldn't load recent activity.",
                        reassurance: 'Your sales and money records are still safe on this device.',
                        onRetry: _retryHomeData,
                      );
                    }
                    if (!snapshot.hasData) {
                      return FulusEmptyState(
                        headline: 'No activity yet today',
                        body: 'Sales, stock, and expenses you record will show up here.',
                        icon: Icons.receipt_long_outlined,
                      );
                    }
                    final transactions = snapshot.data!;
                    if (transactions.isEmpty) {
                      return FulusCard(
                        child: FulusEmptyState(
                          headline: 'No activity yet today',
                          body: 'Sales, stock, and expenses you record will show up here.',
                          icon: Icons.receipt_long_outlined,
                        ),
                      );
                    }
                    return FulusCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < transactions.length.clamp(0, 5); i++) ...[
                            if (i > 0) const FulusListDivider(),
                            MoneyTransactionTile(
                              transaction: transactions[i],
                              currencySymbol: currencySymbol,
                              showDate: false,
                              onTap: () => context.pushNamed(
                                'moneyTransactionDetail',
                                pathParameters: {'id': transactions[i].id},
                                extra: transactions[i],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_businessProfileProvider);
    final profile = profileAsync.value;
    final businessName = profile?.businessName ?? '';
    final greeting = greetingForHour(DateTime.now().hour);
    final user = ref.watch(sessionProvider);
    final isOwner = user == null || user.role == AuthRole.owner;
    final avatarName = isOwner ? (businessName.isEmpty ? '?' : businessName) : user.fullName;
    final headline = isOwner ? (businessName.isEmpty ? 'Fulus' : businessName) : user.fullName;

    return Row(
      children: [
        FulusAvatar(name: avatarName, size: 44),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(greeting, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Switch account',
          onPressed: () => _openAccountSheet(context, ref, user: user),
        ),
      ],
    );
  }

  void _openAccountSheet(BuildContext context, WidgetRef ref, {required AuthUser? user}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user != null) ...[
              Text('Signed in as', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(sheetContext))),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${user.fullName} · ${_roleLabel(user.role)}',
                style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(sheetContext)),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Switch account',
                variant: FulusButtonVariant.secondary,
                onPressed: () => _switchAccount(sheetContext, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchAccount(BuildContext sheetContext, WidgetRef ref) async {
    Navigator.of(sheetContext).pop();
    await ref.read(authRepositoryProvider).logout();
    ref.read(sessionProvider.notifier).state = null;
  }
}

String _roleLabel(AuthRole role) {
  switch (role) {
    case AuthRole.owner:
      return 'Owner';
    case AuthRole.manager:
      return 'Manager';
    case AuthRole.cashier:
      return 'Cashier';
    case AuthRole.employee:
      return 'Employee';
  }
}

final _businessProfileProvider = StreamProvider.autoDispose<BusinessProfile?>((ref) {
  return ref.watch(businessSettingsRepositoryProvider).watchSettings();
});

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 176,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceAltOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusSkeletonBox(width: 100, height: 14),
          SizedBox(height: AppSpacing.md),
          FulusSkeletonBox(width: 180, height: 32),
          SizedBox(height: AppSpacing.sm),
          FulusSkeletonBox(width: 90, height: 14),
        ],
      ),
    );
  }
}

class _NoticeSkeleton extends StatelessWidget {
  const _NoticeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: FulusSkeletonBox(height: 92)),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: FulusSkeletonBox(height: 92)),
      ],
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.state, required this.currencySymbol});
  final HomeHeroState state;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (topLabel, amount, count, emphasizeAction) = switch (state) {
      NotYetOpenedHero(:final yesterdayTotal, :final yesterdaySalesCount) => ('Yesterday', yesterdayTotal, yesterdaySalesCount, false),
      OpenHero(:final todayTotal, :final todaySalesCount, :final closeShopEmphasized) => ('Today · Open', todayTotal, todaySalesCount, closeShopEmphasized),
      ClosedHero(:final finalTotal, :final finalSalesCount) => ('Today · Closed', finalTotal, finalSalesCount, false),
      EmployeeShiftHero(:final shiftTotal, :final shiftSalesCount) => ('Your shift', shiftTotal, shiftSalesCount, false),
    };

    String? trendLabel;
    bool trendUp = true;
    if (state case OpenHero(:final todayTotal, :final yesterdayTotal) when yesterdayTotal > 0) {
      final delta = ((todayTotal - yesterdayTotal) / yesterdayTotal) * 100;
      trendUp = delta >= 0;
      trendLabel = '${delta.abs().round()}% vs yesterday';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppGradients.heroOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(Icons.storefront, size: 128, color: AppColors.onPrimaryOf(context).withValues(alpha: 0.08)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.onPrimaryOf(context), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        topLabel.toUpperCase(),
                        style: AppTypography.label.copyWith(color: AppColors.onPrimaryOf(context).withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                  if (trendLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.onPrimaryOf(context).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendUp ? Icons.arrow_upward : Icons.arrow_downward, size: AppIconSize.dense, color: AppColors.onPrimaryOf(context)),
                          const SizedBox(width: 2),
                          Text(
                            trendLabel,
                            style: AppTypography.caption.copyWith(color: AppColors.onPrimaryOf(context), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                formatMoney(amount, symbol: currencySymbol),
                style: AppTypography.display.copyWith(
                  color: AppColors.onPrimaryOf(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$count sale${count == 1 ? '' : 's'} so far',
                style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withValues(alpha: 0.75)),
              ),
              if (state is NotYetOpenedHero) ...[
                const SizedBox(height: AppSpacing.lg),
                _HeroButton(
                  label: 'Open Shop',
                  onTap: () async {
                    final opened = await showOpeningFloatSheet(context);
                    if (opened && context.mounted) {
                      showFulusSnackbar(context, message: 'Shop opened. Have a great day!');
                      ref.read(dataRefreshSignalProvider.notifier).state++;
                    }
                  },
                ),
              ] else if (state is OpenHero) ...[
                const SizedBox(height: AppSpacing.lg),
                _HeroButton(
                  label: 'Close Shop',
                  emphasized: emphasizeAction,
                  onTap: () => context.pushNamed('moneyDailyClosingCount'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, required this.onTap, this.emphasized = true});
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final onPrimary = AppColors.onPrimaryOf(context);
    return SizedBox(
      width: double.infinity,
      height: AppTouchTarget.minimum,
      child: emphasized
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: onPrimary,
                foregroundColor: AppColors.primaryOf(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: onTap,
              child: _HeroButtonLabel(label: label),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: onPrimary,
                side: BorderSide(color: onPrimary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: onTap,
              child: _HeroButtonLabel(label: label),
            ),
    );
  }
}

class _HeroButtonLabel extends StatelessWidget {
  const _HeroButtonLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: AppTypography.buttonLabel),
        const SizedBox(width: AppSpacing.xs),
        const Icon(Icons.arrow_forward, size: AppIconSize.compact),
      ],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.selection, required this.currencySymbol});
  final SecondaryNoticeSelection selection;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    if (selection.shown.length == 1) {
      return SizedBox(width: double.infinity, child: _noticeTile(context, selection.shown.first));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < selection.shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 152, child: _noticeTile(context, selection.shown[i])),
                ],
              ],
            ),
          ),
        ),
        if (selection.overflowCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'and ${selection.overflowCount} more',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ],
    );
  }

  Widget _noticeTile(BuildContext context, SecondaryNotice notice) {
    switch (notice.type) {
      case SecondaryNoticeType.lowStock:
        return FulusStatCard(
          label: notice.label,
          value: notice.value.toInt().toString(),
          icon: Icons.inventory_2_outlined,
          valueColor: AppColors.warningOf(context),
          onTap: () => context.goNamed('stock'),
        );
      case SecondaryNoticeType.pendingCredit:
        return FulusStatCard(
          label: notice.label,
          value: formatMoney(notice.value.toDouble(), symbol: currencySymbol, compact: true),
          icon: Icons.request_page_outlined,
          valueColor: AppColors.infoOf(context),
          onTap: () => context.pushNamed('moneyCustomers'),
        );
      case SecondaryNoticeType.unsyncedItems:
        return FulusStatCard(
          label: notice.label,
          value: notice.value.toInt().toString(),
          icon: Icons.cloud_upload_outlined,
          valueColor: AppColors.textSecondaryOf(context),
          onTap: () => context.pushNamed('moreSyncDetail'),
        );
    }
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FulusQuickAction(
            icon: Icons.point_of_sale_outlined,
            label: 'Sell',
            onTap: () => context.goNamed('sell'),
          ),
        ),
        Expanded(
          child: FulusQuickAction(
            icon: Icons.inventory_2_outlined,
            label: 'Add stock',
            onTap: () => context.pushNamed('stockAddProduct'),
          ),
        ),
        Expanded(
          child: FulusQuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'Add expense',
            onTap: () => context.pushNamed('moneyAddExpense'),
          ),
        ),
        Expanded(
          child: FulusQuickAction(
            icon: Icons.bar_chart_outlined,
            label: 'Reports',
            onTap: () => context.pushNamed('moreReports'),
          ),
        ),
      ],
    );
  }
}
