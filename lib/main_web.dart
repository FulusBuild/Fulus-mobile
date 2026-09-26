import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'shared/widgets/fulus_action_tile.dart';
import 'shared/widgets/fulus_card.dart';
import 'shared/widgets/fulus_chip.dart';
import 'shared/widgets/fulus_screen.dart';
import 'shared/widgets/fulus_section_header.dart';

/// Web-only visual QA entrypoint.
///
/// The production entrypoint remains [main.dart]. This target deliberately
/// avoids device-only bootstrap services so the Fulus interaction language can
/// be inspected in a browser at phone/tablet widths without an APK.
void main() {
  runApp(const FulusWebVisualQaApp());
}

class FulusWebVisualQaApp extends StatelessWidget {
  const FulusWebVisualQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fulus Visual QA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const FulusWebHomeFixture(),
    );
  }
}

class FulusWebHomeFixture extends StatefulWidget {
  const FulusWebHomeFixture({super.key});

  @override
  State<FulusWebHomeFixture> createState() => _FulusWebHomeFixtureState();
}

class _FulusWebHomeFixtureState extends State<FulusWebHomeFixture> {
  var _selectedNav = 0;
  var _selectedPeriod = 'Today';

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Good morning',
      subtitle: 'Fulus Demo Business • Main location',
      applyPadding: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 700 ? 32.0 : 20.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FulusCard(
                  elevated: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FulusStatusPill(
                        label: 'Cloud connected',
                        icon: Icons.cloud_done_outlined,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sales today',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '₦248,500',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '18 sales • 12% above yesterday',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const FulusSectionHeader(
                  title: 'Quick actions',
                  subtitle: 'The things you do most',
                ),
                LayoutBuilder(
                  builder: (context, tileConstraints) {
                    final columns = tileConstraints.maxWidth >= 620 ? 2 : 1;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 2 ? 2.4 : 3.0,
                      children: const [
                        FulusActionTile(
                          icon: Icons.point_of_sale_outlined,
                          label: 'New sale',
                          subtitle: 'Start selling',
                          onTap: null,
                        ),
                        FulusActionTile(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock',
                          subtitle: 'Check inventory',
                          onTap: null,
                        ),
                        FulusActionTile(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Money',
                          subtitle: 'View cash and activity',
                          onTap: null,
                        ),
                        FulusActionTile(
                          icon: Icons.bar_chart_outlined,
                          label: 'Reports',
                          subtitle: 'See business performance',
                          onTap: null,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                FulusSectionHeader(
                  title: 'Business overview',
                  action: 'See all',
                  onActionTap: () {},
                ),
                const FulusStatGrid(
                  cards: [
                    FulusStatCard(
                      label: 'Transactions',
                      value: '18',
                      icon: Icons.receipt_long_outlined,
                    ),
                    FulusStatCard(
                      label: 'Items sold',
                      value: '47',
                      icon: Icons.shopping_bag_outlined,
                    ),
                    FulusStatCard(
                      label: 'Low stock',
                      value: '6',
                      icon: Icons.warning_amber_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const FulusSectionHeader(
                  title: 'Recent activity',
                  subtitle: 'Latest business events',
                ),
                FulusChipRow(
                  children: [
                    FulusChip(
                      label: 'Today',
                      selected: _selectedPeriod == 'Today',
                      onTap: () => setState(() => _selectedPeriod = 'Today'),
                    ),
                    FulusChip(
                      label: 'Yesterday',
                      selected: _selectedPeriod == 'Yesterday',
                      onTap: () => setState(() => _selectedPeriod = 'Yesterday'),
                    ),
                    FulusChip(
                      label: 'This week',
                      selected: _selectedPeriod == 'This week',
                      onTap: () => setState(() => _selectedPeriod = 'This week'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const FulusCard(
                  child: Column(
                    children: [
                      _ActivityRow(
                        icon: Icons.point_of_sale_outlined,
                        title: 'Sale #1048',
                        subtitle: '2 items • Cash',
                        amount: '₦18,500',
                      ),
                      Divider(height: 24),
                      _ActivityRow(
                        icon: Icons.inventory_2_outlined,
                        title: 'Stock adjusted',
                        subtitle: 'Rice 25kg • +10 units',
                        amount: '+10',
                      ),
                      Divider(height: 24),
                      _ActivityRow(
                        icon: Icons.payments_outlined,
                        title: 'Expense recorded',
                        subtitle: 'Transport',
                        amount: '₦4,000',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Web visual QA fixture • ' + _selectedPeriod.toLowerCase(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _WebQaBottomNavigationBar(
        selectedIndex: _selectedNav,
        onSelected: (index) => setState(() => _selectedNav = index),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              amount,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}


class _WebQaBottomNavigationBar extends StatelessWidget {
  const _WebQaBottomNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Sell'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Stock'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Money'),
    (Icons.more_horiz, Icons.more_horiz, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;

    return Material(
      color: surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border.withValues(alpha: .7))),
        ),
        padding: EdgeInsets.fromLTRB(
          4,
          4,
          4,
          bottomInset > 0 ? 4 : 8,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: selectedIndex == index,
                    label: _items[index].$3,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSelected(index),
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: selectedIndex == index
                                    ? primary.withValues(alpha: .10)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selectedIndex == index ? _items[index].$2 : _items[index].$1,
                                    size: 24,
                                    color: selectedIndex == index
                                        ? primary
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _items[index].$3,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontWeight: selectedIndex == index
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selectedIndex == index
                                            ? primary
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
