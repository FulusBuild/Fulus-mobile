import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/dashboard_summary.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import '../../../money/presentation/widgets/opening_float_sheet.dart';

/// Volume 4: "one evolving hero element... not five widgets shown at
/// once." This screen is deliberately thin — everything that decides
/// WHICH hero to show lives in DashboardEngine; this file only renders
/// whichever [HomeHeroState] it's handed.
///
/// [currentAuthUserId] / [isOwner] are passed in from wherever Stage 2's
/// session lives (not built by this module — see dashboard_repository
/// .dart's own doc). Left as required constructor params rather than
/// read from a session provider this module can't see, so this screen
/// compiles and is testable in isolation; the merge step is one line at
/// the call site once Stage 2's session provider exists.
///
/// Foundation follow-up: every color here now goes through the
/// brightness-aware `AppColors.*Of(context)` accessors (design_tokens
/// .dart) instead of the flat Light-suffixed constants this screen used
/// before — it previously ignored `ThemeMode.system` entirely despite
/// that being wired in app.dart, a real, visible bug on a device set to
/// dark mode. No layout or structure changed, only which token each
/// color reads from.
///
/// Foundation follow-up (Money): Open Shop / Close Shop were wired to
/// nothing (`onTap: () {}`) — they now open the Money feature's
/// opening-float sheet and Daily Closing flow respectively, the two
/// places Volume 8 names these buttons as the trigger for.
///
/// Gap fix (was: "closing a mock day here doesn't flip this screen's
/// own hero state"): [HomeHeroState] still comes entirely from
/// [DashboardRepository] — untouched — but this screen now also
/// listens to [dashboardRefreshSignalProvider] and re-fetches whenever
/// it changes. Opening or closing the drawer bumps that signal (see
/// `daily_closing_count_screen.dart`), so returning to this tab after
/// either action now shows the real, current state instead of whatever
/// was cached from this screen's last `initState`. Home stays on a
/// plain Future rather than converting to a Riverpod provider itself —
/// see this class's own next paragraph for why that's deliberate.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(dashboardRepositoryProvider);
    _heroFuture = repo.getHeroState(currentAuthUserId: widget.currentAuthUserId, isOwner: widget.isOwner);
    _noticesFuture = repo.getSecondaryNotices();
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture]);
  }

  @override
  Widget build(BuildContext context) {
    // Gap fix — see this class's header comment. Any bump of this
    // signal (Open Shop below, or Daily Closing elsewhere) means the
    // real data behind the hero has changed, so re-fetch. `ref.listen`
    // rather than `ref.watch` deliberately: this screen still owns its
    // own Future/setState fetch cycle (unchanged from before), this
    // just triggers that same cycle from a second place.
    ref.listen<int>(dashboardRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) setState(_load);
    });
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              FutureBuilder<HomeHeroState>(
                future: _heroFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _HeroCard(state: snapshot.data!, currencySymbol: currencySymbol);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (widget.isOwner)
                FutureBuilder<SecondaryNoticeSelection>(
                  future: _noticesFuture,
                  builder: (context, snapshot) {
                    final selection = snapshot.data;
                    if (selection == null || selection.shown.isEmpty) return const SizedBox.shrink();
                    return _SecondaryNotices(selection: selection);
                  },
                ),
            ],
          ),
        ),
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
    final (label, amount, count, emphasizeAction) = switch (state) {
      NotYetOpenedHero(:final yesterdayTotal, :final yesterdaySalesCount) => (
          'Yesterday',
          yesterdayTotal,
          yesterdaySalesCount,
          false,
        ),
      OpenHero(:final todayTotal, :final todaySalesCount, :final closeShopEmphasized) => (
          'Today so far',
          todayTotal,
          todaySalesCount,
          closeShopEmphasized,
        ),
      ClosedHero(:final finalTotal, :final finalSalesCount) => ('Today (closed)', finalTotal, finalSalesCount, false),
      EmployeeShiftHero(:final shiftTotal, :final shiftSalesCount) => ('Your shift', shiftTotal, shiftSalesCount, false),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withOpacity(0.7))),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$currencySymbol${amount.toStringAsFixed(2)}',
            style: AppTypography.display.copyWith(color: AppColors.onPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$count sale${count == 1 ? '' : 's'}',
            style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withOpacity(0.7)),
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
                  ref.read(dashboardRefreshSignalProvider.notifier).state++;
                }
              },
            ),
          ] else if (emphasizeAction) ...[
            const SizedBox(height: AppSpacing.lg),
            _HeroButton(
              label: 'Close Shop',
              onTap: () => context.goNamed('moneyDailyClosingCount'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppTouchTarget.minimum,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.onPrimaryOf(context),
          foregroundColor: AppColors.primaryOf(context),
        ),
        onPressed: onTap,
        child: Text(label, style: AppTypography.buttonLabel),
      ),
    );
  }
}

class _SecondaryNotices extends StatelessWidget {
  const _SecondaryNotices({required this.selection});
  final SecondaryNoticeSelection selection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final notice in selection.shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warningOf(context).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warningOf(context), size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${notice.label}: ${notice.value}',
                      style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (selection.overflowCount > 0)
          Text(
            'and ${selection.overflowCount} more',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
      ],
    );
  }
}
