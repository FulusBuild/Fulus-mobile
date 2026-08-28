import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
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
/// never the business total") is *not* overridden: everything below
/// the hero here is business-wide data an employee's role can't even
/// navigate to (Money and Reports are owner-only branches — see
/// app_shell.dart), so it all stays gated behind [isOwner], and the
/// employee hero keeps its original single-card presentation, just
/// carried over onto the same visual language (gradient, formatting).
///
/// [currentAuthUserId] / [isOwner] are passed in from wherever Stage 2's
/// session lives (not built by this module — see dashboard_repository
/// .dart's own doc). Left as required constructor params rather than
/// read from a session provider this module can't see, so this screen
/// compiles and is testable in isolation; the merge step is one line at
/// the call site once Stage 2's session provider exists.
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
  const HomeScreen({super.key, required this.currentAuthUserId, required this.isOwner});

  final String currentAuthUserId;
  final bool isOwner;

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
    _heroFuture = repo.getHeroState(currentAuthUserId: widget.currentAuthUserId, isOwner: widget.isOwner);
    // Redesign pass — max: 3 so Home's notice row can show all three
    // categories at once (see dashboard_repository.dart's own doc on
    // this parameter); every other caller of this method keeps the
    // default cap of 2.
    _noticesFuture = repo.getSecondaryNotices(max: 3);
    _activityFuture = widget.isOwner
        ? ref.read(moneyRepositoryProvider).getTransactions(_reportsEngine.resolvePeriod(ReportPeriodKind.today))
        : Future.value(const <MoneyTransaction>[]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture, _activityFuture]);
  }

  @override
  Widget build(BuildContext context) {
    // Gap fix — see this class's header comment. Any bump of this
    // signal (Open Shop below, or Daily Closing elsewhere) means the
    // real data behind the hero has changed, so re-fetch. `ref.listen`
    // rather than `ref.watch` deliberately: this screen still owns its
    // own Future/setState fetch cycle (unchanged from before), this
    // just triggers that same cycle from a second place.
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
              if (widget.isOwner) ...[
                const _GreetingHeader(),
                const SizedBox(height: AppSpacing.lg),
              ],
              FutureBuilder<HomeHeroState>(
                future: _heroFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const _HeroSkeleton();
                  }
                  return _HeroCard(state: snapshot.data!, currencySymbol: currencySymbol);
                },
              ),
              if (widget.isOwner) ...[
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<SecondaryNoticeSelection>(
                  future: _noticesFuture,
                  builder: (context, snapshot) {
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
                  onActionTap: () => context.goNamed('moneyHistory'),
                ),
                FutureBuilder<List<MoneyTransaction>>(
                  future: _activityFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]);
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

/// Business name, a "Good morning"-style greeting, an initials avatar,
/// Business name, a "Good morning"-style greeting, and an initials
/// avatar — the header the reference design calls for. Its own widget
/// (rather than inline in `build`) purely to keep
/// `_HomeScreenState.build` scannable.
///
/// Deliberately does NOT duplicate a sync-status pill here — that was
/// this pass's first draft, and it was wrong: `app_shell.dart`'s own
/// `_SyncStatusIndicator` already renders the identical [SyncStatus] as
/// an icon in the same top-right corner, on every screen including this
/// one, so a second "Sync off" pill right underneath it was reporting
/// the same fact twice in the same glance. No other screen in this app
/// duplicates that indicator; Home shouldn't either.
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_businessProfileProvider);
    final profile = profileAsync.value;
    final businessName = profile?.businessName ?? '';
    final greeting = greetingForHour(DateTime.now().hour);

    return Row(
      children: [
        FulusAvatar(name: businessName.isEmpty ? '?' : businessName, size: 44),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(greeting, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              Text(
                businessName.isEmpty ? 'Fulus' : businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Business-wide profile stream, scoped to this screen — mirrors
/// `money_providers.dart`'s own `moneyCurrencySymbolProvider` (same
/// underlying `businessSettingsRepositoryProvider.watchSettings()`
/// call); kept local rather than promoted to a shared provider since
/// Home is the only place currently reading the business name itself.
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

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.state, required this.currencySymbol});
  final HomeHeroState state;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Redesign pass — one explicit label per state rather than the
    // earlier "label · statusLabel" concatenation, which produced a
    // literal "TODAY (CLOSED) · CLOSED" for the closed state (both
    // halves said the same thing) — caught on-device after this pass
    // first shipped. Each state now owns its full top-line wording
    // directly, so there's no combination step left to go wrong.
    final (topLabel, amount, count, emphasizeAction) = switch (state) {
      NotYetOpenedHero(:final yesterdayTotal, :final yesterdaySalesCount) => (
          'Yesterday',
          yesterdayTotal,
          yesterdaySalesCount,
          false,
        ),
      OpenHero(:final todayTotal, :final todaySalesCount, :final closeShopEmphasized) => (
          'Today · Open',
          todayTotal,
          todaySalesCount,
          closeShopEmphasized,
        ),
      ClosedHero(:final finalTotal, :final finalSalesCount) => (
          'Today · Closed',
          finalTotal,
          finalSalesCount,
          false,
        ),
      EmployeeShiftHero(:final shiftTotal, :final shiftSalesCount) => (
          'Your shift',
          shiftTotal,
          shiftSalesCount,
          false,
        ),
    };

    // Redesign pass — only rendered for OpenHero, and only once a real
    // yesterday baseline exists (never "0% vs yesterday" from a missing
    // comparison — see OpenHero.yesterdayTotal's own doc comment).
    //
    // `if (state case OpenHero(...))` rather than `if (state is
    // OpenHero) { state.yesterdayTotal }` deliberately — [state] is a
    // public field here, and Dart only promotes private fields (or
    // locals) after an `is` check, so the `is`-then-access form fails
    // to compile with "getter isn't defined for HomeHeroState". Pattern
    // matching destructures directly and sidesteps promotion entirely
    // — same mechanism the switch above already uses.
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
                          Icon(
                            trendUp ? Icons.arrow_upward : Icons.arrow_downward,
                            size: AppIconSize.dense,
                            color: AppColors.onPrimaryOf(context),
                          ),
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
                      // Gap fix — see HomeScreen's header comment. Opening
                      // the drawer changes exactly what this hero should
                      // show (NotYetOpened → Open); without this, Home kept
                      // showing "Ready to open?" until the next manual
                      // pull-to-refresh.
                      ref.read(dataRefreshSignalProvider.notifier).state++;
                    }
                  },
                ),
              ] else if (state is OpenHero) ...[
                const SizedBox(height: AppSpacing.lg),
                // Bug fix (UX audit): this used to be gated behind
                // `emphasizeAction`, so for the entire middle of a normal
                // business day — OpenHero with closeShopEmphasized false,
                // the state Home spends most of its life in — no Close
                // Shop button rendered at all, and nothing else on this
                // screen reaches Daily Closing either. Close Shop should
                // read as "available the entire time, just visually
                // stronger near closing," not "appears near closing."
                // `emphasized` below is still what carries that visual
                // distinction; only reachability changed here.
                _HeroButton(
                  label: 'Close Shop',
                  emphasized: emphasizeAction,
                  onTap: () => context.goNamed('moneyDailyClosingCount'),
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

  /// Bug fix (UX audit) — Close Shop now renders throughout OpenHero,
  /// not just when emphasized, so it needs a visual weight below its
  /// original solid-fill treatment for the ordinary case, reserving that
  /// original look for when it's genuinely emphasized (near closing, or
  /// Open Shop, which is always the one action on its own screen and
  /// stays solid via this parameter's default).
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

/// Redesign pass — replaces the old single-column bordered-box list
/// with a horizontal row of [FulusStatCard]s (the same widget Money and
/// Stock already use for their own overview numbers, per that widget's
/// own doc comment anticipating "any future dashboard summary"), one
/// per [SecondaryNotice]. Tapping a tile routes to wherever that notice
/// is actionable — Stock for low stock, the Credit Book for pending
/// credit, Sync detail for unsynced items.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.selection, required this.currencySymbol});
  final SecondaryNoticeSelection selection;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    // Redesign pass — a lone notice (the common case: usually only one
    // of low-stock/pending-credit/unsynced is actually nonzero at a
    // time) now fills the row instead of sitting in a 152dp-wide card
    // inside a horizontal scroller built for two or three, which left
    // the rest of the row visibly empty (seen on-device with just the
    // "Unsynced" tile).
    if (selection.shown.length == 1) {
      return SizedBox(width: double.infinity, child: _noticeTile(context, selection.shown.first));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: selection.shown.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final notice = selection.shown[i];
              return SizedBox(width: 152, child: _noticeTile(context, notice));
            },
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
          onTap: () => context.goNamed('moneyCustomers'),
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

/// Sell / Add stock / Add expense / Reports — the reference design's
/// shortcut row. Deliberately just navigation, no numbers, so it reads
/// as a different kind of thing than [_NoticeRow]'s stat tiles right
/// above it (see [FulusQuickAction]'s own doc comment).
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
            // pushNamed, not goNamed — Sell above is the root of its
            // own shell branch, so `go` switches straight to it with
            // nothing else involved. This one and the two below are
            // *nested* routes inside a branch (Stock/Money/More) Home
            // hasn't necessarily visited yet this session — `go`-ing
            // straight to a deep route makes StatefulShellRoute build
            // that branch's own root screen first to establish it,
            // then navigate deeper, which is the flash to one screen
            // before landing on the right one. `push` opens the target
            // directly above the shell instead, skipping all of that.
            onTap: () => context.pushNamed('stockRecordMovement'),
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
