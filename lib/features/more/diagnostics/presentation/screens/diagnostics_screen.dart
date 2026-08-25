import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/diagnostics/models/diagnostic_event.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/formatting.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../widgets/diagnostic_style.dart';

/// More -> Diagnostics -> Error Logs — the diagnostic-system brief's
/// own Section 9 ("a screen inside the app where a developer/tester can
/// view recent crash logs, filter, search, and share").
///
/// Genuinely a developer/technician surface, not an ordinary-cashier
/// one — reached only via More, several taps deep, matching Section 16's
/// "should not alarm a non-technical business owner" by placement alone
/// (nothing about a normal day at the till ever routes here on its
/// own). What's shown here is still written in plain language rather
/// than raw exception dumps up front, though — see this file's own
/// list-row copy and DiagnosticDetailScreen's "Likely cause" framing —
/// since a technician using this screen still benefits from a plain
/// explanation before the expandable technical detail underneath it.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

enum _QuickFilter { all, errors, warnings, database, network, sync, sales, inventory }

extension on _QuickFilter {
  String get label {
    switch (this) {
      case _QuickFilter.all:
        return 'All';
      case _QuickFilter.errors:
        return 'Errors';
      case _QuickFilter.warnings:
        return 'Warnings';
      case _QuickFilter.database:
        return 'Database';
      case _QuickFilter.network:
        return 'Network';
      case _QuickFilter.sync:
        return 'Sync';
      case _QuickFilter.sales:
        return 'Sales';
      case _QuickFilter.inventory:
        return 'Inventory';
    }
  }

  bool matches(DiagnosticEvent event) {
    switch (this) {
      case _QuickFilter.all:
        return true;
      case _QuickFilter.errors:
        return event.severity == DiagnosticSeverity.critical ||
            event.severity == DiagnosticSeverity.error;
      case _QuickFilter.warnings:
        return event.severity == DiagnosticSeverity.warning;
      case _QuickFilter.database:
        return event.category == DiagnosticCategory.database;
      case _QuickFilter.network:
        return event.category == DiagnosticCategory.network;
      case _QuickFilter.sync:
        return event.category == DiagnosticCategory.synchronization;
      case _QuickFilter.sales:
        return event.category == DiagnosticCategory.sales;
      case _QuickFilter.inventory:
        return event.category == DiagnosticCategory.inventory;
    }
  }
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  _QuickFilter _filter = _QuickFilter.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(diagnosticEventsProvider);

    return FulusScreen(
      title: 'Diagnostics',
      applyPadding: false,
      body: eventsAsync.when(
        loading: () => const FulusLoadingIndicator(),
        error: (error, stack) => FulusErrorState(
          message: "Couldn't load diagnostics.",
          reassurance: 'Nothing about your business data is affected — this is only '
              'about viewing this log.',
          onRetry: () => ref.invalidate(diagnosticEventsProvider),
        ),
        data: (events) => _DiagnosticsList(
          allEvents: events,
          filter: _filter,
          search: _search,
          onFilterChanged: (f) => setState(() => _filter = f),
          onSearchChanged: (s) => setState(() => _search = s),
        ),
      ),
    );
  }
}

class _DiagnosticsList extends StatelessWidget {
  const _DiagnosticsList({
    required this.allEvents,
    required this.filter,
    required this.search,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  final List<DiagnosticEvent> allEvents;
  final _QuickFilter filter;
  final String search;
  final ValueChanged<_QuickFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final errorCount = allEvents
        .where((e) => e.severity == DiagnosticSeverity.critical || e.severity == DiagnosticSeverity.error)
        .length;
    final warningCount = allEvents.where((e) => e.severity == DiagnosticSeverity.warning).length;

    final needle = search.trim().toLowerCase();
    final visibleEvents = allEvents.where((e) {
      if (!filter.matches(e)) return false;
      if (needle.isEmpty) return true;
      final haystack = '${e.title} ${e.message} ${e.component ?? ''}'.toLowerCase();
      return haystack.contains(needle);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: _SummaryHeader(
            errorCount: errorCount,
            warningCount: warningCount,
            totalCount: allEvents.length,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: FulusSearchField(hintText: 'Search diagnostics…', onChanged: onSearchChanged),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: FulusChipRow(
            children: _QuickFilter.values
                .map((f) => FulusChip(
                      label: f.label,
                      selected: filter == f,
                      onTap: () => onFilterChanged(f),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: visibleEvents.isEmpty
              ? FulusEmptyState(
                  headline: allEvents.isEmpty ? 'No issues recorded' : 'No matching events',
                  body: allEvents.isEmpty
                      ? "Fulus hasn't run into anything worth logging yet."
                      : 'Try a different filter or search term.',
                  icon: Icons.check_circle_outline,
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: visibleEvents.length,
                  separatorBuilder: (_, __) => const FulusListDivider(),
                  itemBuilder: (context, index) => _EventRow(event: visibleEvents[index]),
                ),
        ),
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.errorCount, required this.warningCount, required this.totalCount});

  final int errorCount;
  final int warningCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: Row(
        children: [
          _StatColumn(label: 'Errors', value: '$errorCount', color: AppColors.errorOf(context)),
          _StatColumn(label: 'Warnings', value: '$warningCount', color: AppColors.warningOf(context)),
          _StatColumn(label: 'Events', value: '$totalCount', color: AppColors.textPrimaryOf(context)),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTypography.heading.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final DiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      '${formatRelativeDay(event.timestamp)}, ${formatTime(event.timestamp)}',
      if (event.component != null) event.component!,
    ];
    return FulusListRow(
      leading: Icon(event.severity.icon, color: event.severity.colorOf(context)),
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitleParts.join(' · ') + (event.occurrenceCount > 1 ? '  ·  ×${event.occurrenceCount}' : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.goNamed('moreDiagnosticDetail', pathParameters: {'eventId': event.id}),
    );
  }
}
