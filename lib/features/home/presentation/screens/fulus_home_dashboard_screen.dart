import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/report.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../../../features/money/domain/money_transaction.dart';
import '../../../../features/money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider, moneyRepositoryProvider;
import '../../../../shared/widgets/widgets.dart';

/// The new Fulus workspace home: deliberately simple, action-first and
/// designed around the swipe navigation drawer instead of persistent tabs.
/// Existing repositories and business rules remain the source of truth.
class FulusHomeDashboardScreen extends ConsumerStatefulWidget {
  const FulusHomeDashboardScreen({
    super.key,
    required this.currentAuthUserId,
    required this.isOwner,
    required this.canViewDashboardStats,
  });

  final String currentAuthUserId;
  final bool isOwner;
  final bool canViewDashboardStats;

  @override
  ConsumerState<FulusHomeDashboardScreen> createState() => _FulusHomeDashboardScreenState();
}

class _FulusHomeDashboardScreenState extends ConsumerState<FulusHomeDashboardScreen> {
  static const _engine = ReportsEngine();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final showBusiness = widget.isOwner || widget.canViewDashboardStats;
    final dashboard = ref.read(dashboardRepositoryProvider);
    final money = ref.read(moneyRepositoryProvider);
    final today = _engine.resolvePeriod(ReportPeriodKind.today);
    final week = _engine.resolvePeriod(ReportPeriodKind.thisWeek);
    _future = Future.wait<dynamic>([
      dashboard.getHeroState(currentAuthUserId: widget.currentAuthUserId, isOwner: showBusiness),
      money.getTransactions(today, currentAuthUserId: widget.currentAuthUserId, canViewAllSales: showBusiness),
      money.getTransactions(week, currentAuthUserId: widget.currentAuthUserId, canViewAllSales: showBusiness),
    ]).then((values) => _HomeData(
          hero: values[0] as HomeHeroState,
          today: values[1] as List<MoneyTransaction>,
          week: values[2] as List<MoneyTransaction>,
        ));
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final user = ref.watch(sessionProvider);
    final businessName = ref.watch(businessSettingsRepositoryProvider).valueOrNull?.businessName;
    final displayName = user?.role == AuthRole.owner
        ? ((businessName?.trim().isNotEmpty ?? false) ? businessName!.trim() : 'Fulus')
        : (user?.fullName.trim().isNotEmpty ?? false ? user!.fullName : 'Fulus');

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_HomeData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingHome();
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _HomeHeader(displayName: displayName),
                    const SizedBox(height: AppSpacing.xl),
                    FulusErrorState(
                      message: "Couldn't load your business summary.",
                      reassurance: 'Your work is still saved on this device.',
                      onRetry: () => setState(_load),
                    ),
                  ],
                );
              }
              return _HomeBody(
                data: snapshot.data!,
                currencySymbol: symbol,
                displayName: displayName,
                isOwner: widget.isOwner,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({required this.hero, required this.today, required this.week});
  final HomeHeroState hero;
  final List<MoneyTransaction> today;
  final List<MoneyTransaction> week;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final greeting = greetingForHour(DateTime.now().hour);
    return Row(
      children: [
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Open navigation',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 26),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fulus', style: AppTypography.title.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('$greeting, $displayName 👋', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.pushNamed('moreNotifications'),
          icon: const Icon(Icons.notifications_none_rounded, size: 25),
        ),
      ],
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data, required this.currencySymbol, required this.displayName, required this.isOwner});
  final _HomeData data;
  final String currencySymbol;
  final String displayName;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final sales = data.today.where((t) => t.type == MoneyTransactionType.saleIncome).fold<double>(0, (sum, t) => sum + t.amount);
    final previous = data.week.where((t) => t.type == MoneyTransactionType.saleIncome).fold<double>(0, (sum, t) => sum + t.amount);
    final count = data.today.where((t) => t.type == MoneyTransactionType.saleIncome).length;
    final recent = data.today.take(5).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 32),
      children: [
        _HomeHeader(displayName: displayName),
        const SizedBox(height: AppSpacing.lg),
        _SalesHero(amount: sales, currencySymbol: currencySymbol, count: count, previous: previous),
        const SizedBox(height: AppSpacing.md),
        const _QuickActions(),
        const SizedBox(height: AppSpacing.xl),
        _WeeklyGraph(transactions: data.week, currencySymbol: currencySymbol),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Text('Recent activity', style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(onPressed: () => context.pushNamed('moneyHistory'), child: const Text('See all')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (recent.isEmpty)
          FulusCard(child: FulusEmptyState(headline: 'No activity yet', body: 'Sales and money activity will appear here.', icon: Icons.receipt_long_outlined))
        else
          FulusCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const FulusListDivider(),
                  _ActivityRow(transaction: recent[i], currencySymbol: currencySymbol),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SalesHero extends StatelessWidget {
  const _SalesHero({required this.amount, required this.currencySymbol, required this.count, required this.previous});
  final double amount;
  final String currencySymbol;
  final int count;
  final double previous;

  @override
  Widget build(BuildContext context) {
    final trend = previous <= 0 ? null : ((amount / previous) - 1) * 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's sales", style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              const Spacer(),
              if (trend != null)
                Text('${trend >= 0 ? '↑' : '↓'} ${trend.abs().round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: trend >= 0 ? Colors.green.shade700 : AppColors.warningOf(context))),
            ],
          ),
          const SizedBox(height: 6),
          Text(formatMoney(amount, symbol: currencySymbol), style: AppTypography.display.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$count sale${count == 1 ? '' : 's'} today', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ActionCard(icon: Icons.point_of_sale_outlined, title: 'Sell', subtitle: 'Quick sale', onTap: () => context.goNamed('sell')),
        _ActionCard(icon: Icons.inventory_2_outlined, title: 'Stock', subtitle: 'View inventory', onTap: () => context.goNamed('stock')),
        _ActionCard(icon: Icons.account_balance_wallet_outlined, title: 'Money', subtitle: 'Transactions', onTap: () => context.goNamed('money')),
        _ActionCard(icon: Icons.bar_chart_outlined, title: 'Reports', subtitle: 'Business insights', onTap: () => context.pushNamed('moreReports')),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderOf(context))),
          child: Row(
            children: [
              Icon(icon, size: 24, color: AppColors.textPrimaryOf(context)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context)))])),
              const Icon(Icons.chevron_right_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyGraph extends StatelessWidget {
  const _WeeklyGraph({required this.transactions, required this.currencySymbol});
  final List<MoneyTransaction> transactions;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final values = List<double>.filled(7, 0);
    for (final transaction in transactions) {
      if (transaction.type != MoneyTransactionType.saleIncome) continue;
      final day = DateTime(transaction.dateTime.year, transaction.dateTime.month, transaction.dateTime.day);
      final index = day.difference(start).inDays;
      if (index >= 0 && index < 7) values[index] += transaction.amount;
    }
    final total = values.fold<double>(0, (a, b) => a + b);
    final labels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.borderOf(context))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text('Sales this week', style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w800)), const Spacer(), Text(formatMoney(total, symbol: currencySymbol, compact: true), style: const TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 18),
          SizedBox(height: 150, child: CustomPaint(painter: _SalesChartPainter(values: values, primary: AppColors.primaryOf(context), text: AppColors.textSecondaryOf(context)))),
          const SizedBox(height: 8),
          Row(children: [for (final label in labels) Expanded(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textSecondaryOf(context))))]),
        ],
      ),
    );
  }
}

class _SalesChartPainter extends CustomPainter {
  const _SalesChartPainter({required this.values, required this.primary, required this.text});
  final List<double> values;
  final Color primary;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);
    final max = maxValue <= 0 ? 1 : maxValue;
    final barWidth = size.width / 7 * .42;
    final baseline = size.height - 8;
    final paint = Paint()..color = primary;
    for (var i = 0; i < values.length; i++) {
      final x = (i + .5) * size.width / 7;
      final h = (values[i] / max) * (size.height - 22);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x - barWidth / 2, baseline - h, barWidth, h), const Radius.circular(7));
      canvas.drawRRect(rect, paint);
    }
    final guide = Paint()..color = text.withValues(alpha: .10)..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 12 + i * (size.height - 32) / 2;
      canvas.drawLine(0, y, size.width, y, guide);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter oldDelegate) => oldDelegate.values != values || oldDelegate.primary != primary;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.transaction, required this.currencySymbol});
  final MoneyTransaction transaction;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final icon = switch (transaction.type) {
      MoneyTransactionType.saleIncome => Icons.shopping_cart_outlined,
      MoneyTransactionType.expense => Icons.payments_outlined,
      _ => Icons.account_balance_wallet_outlined,
    };
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 18, backgroundColor: AppColors.primaryOf(context).withValues(alpha: .10), child: Icon(icon, size: 18, color: AppColors.primaryOf(context))),
      title: Text(transaction.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatRelativeTime(transaction.dateTime), style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
      trailing: Text(formatMoney(transaction.signedAmount, symbol: currencySymbol, showSign: true), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _LoadingHome extends StatelessWidget {
  const _LoadingHome();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: const [FulusSkeletonBox(height: 48), SizedBox(height: 20), FulusSkeletonBox(height: 130), SizedBox(height: 12), FulusSkeletonBox(height: 160), SizedBox(height: 20), FulusSkeletonBox(height: 220)]);
}
