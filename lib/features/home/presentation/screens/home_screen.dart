import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/dashboard_summary.dart';

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
                  return _HeroCard(state: snapshot.data!);
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.state});
  final HomeHeroState state;

  @override
  Widget build(BuildContext context) {
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
            '₦${amount.toStringAsFixed(2)}',
            style: AppTypography.display.copyWith(color: AppColors.onPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$count sale${count == 1 ? '' : 's'}',
            style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withOpacity(0.7)),
          ),
          if (state is NotYetOpenedHero) ...[
            const SizedBox(height: AppSpacing.lg),
            _HeroButton(label: 'Open Shop', onTap: () {}),
          ] else if (emphasizeAction) ...[
            const SizedBox(height: AppSpacing.lg),
            _HeroButton(label: 'Close Shop', onTap: () {}),
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
