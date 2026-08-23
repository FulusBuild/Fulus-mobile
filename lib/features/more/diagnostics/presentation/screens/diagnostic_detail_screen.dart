import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/diagnostics/export/diagnostic_share_service.dart';
import '../../../../../core/diagnostics/models/diagnostic_enums.dart';
import '../../../../../core/diagnostics/models/diagnostic_event.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/formatting.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../widgets/diagnostic_style.dart';

/// One captured [DiagnosticEvent], in full — brief Section 10's own
/// mockup shape: likely cause + confidence up front in plain language,
/// then where/evidence/recent-activity, with the raw exception and
/// stack trace tucked into a collapsed "Technical details" section
/// rather than shown by default (Section 16: plain language first, raw
/// detail available but not the first thing on screen).
class DiagnosticDetailScreen extends ConsumerStatefulWidget {
  const DiagnosticDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<DiagnosticDetailScreen> createState() => _DiagnosticDetailScreenState();
}

class _DiagnosticDetailScreenState extends ConsumerState<DiagnosticDetailScreen> {
  bool _markedViewed = false;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(diagnosticEventByIdProvider(widget.eventId));

    return FulusScreen(
      title: 'Error details',
      actions: [
        eventAsync.maybeWhen(
          data: (event) => event == null
              ? const SizedBox.shrink()
              : IconButton(
                  icon: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  onPressed: _sharing ? null : () => _showShareOptions(context, event),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
      body: eventAsync.when(
        loading: () => const FulusLoadingIndicator(),
        error: (error, stack) => const FulusErrorState(message: "Couldn't load this event."),
        data: (event) {
          if (event == null) {
            return const FulusEmptyState(
              headline: 'Not found',
              body: 'This event may have been cleared by the retention policy.',
              icon: Icons.search_off,
            );
          }
          if (!_markedViewed) {
            _markedViewed = true;
            // Fire-and-forget, purely cosmetic (an unread indicator) —
            // see DriftDiagnosticStore.markViewed's own doc comment.
            ref.read(diagnosticLoggerProvider).markViewed(event.id);
          }
          return _DetailBody(event: event);
        },
      ),
    );
  }

  Future<void> _showShareOptions(BuildContext context, DiagnosticEvent event) async {
    final choice = await showFulusBottomSheet<_ShareChoice>(
      context: context,
      title: 'Share diagnostics',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusListRow(
            title: const Text('This error'),
            subtitle: const Text('Just this event'),
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.thisError),
          ),
          FulusListRow(
            title: const Text("Today's logs"),
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.today),
          ),
          FulusListRow(
            title: const Text('Last 7 days'),
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.last7Days),
          ),
          FulusListRow(
            title: const Text('Full diagnostic report'),
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.full),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _sharing = true);
    try {
      final shareService = DiagnosticShareService();
      final logger = ref.read(diagnosticLoggerProvider);
      switch (choice) {
        case _ShareChoice.thisError:
          await shareService.shareEvent(event);
        case _ShareChoice.today:
          final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          final events = await logger.getForExport(filter: DiagnosticFilter(startDate: startOfDay));
          await shareService.shareRange(events: events, rangeLabel: "Today's logs");
        case _ShareChoice.last7Days:
          final start = DateTime.now().subtract(const Duration(days: 7));
          final events = await logger.getForExport(filter: DiagnosticFilter(startDate: start));
          await shareService.shareRange(events: events, rangeLabel: 'Last 7 days');
        case _ShareChoice.full:
          final events = await logger.getForExport();
          await shareService.shareRange(events: events, rangeLabel: 'Full diagnostic report');
      }
    } catch (_) {
      if (mounted) {
        showFulusSnackbar(context, message: "Couldn't share right now. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

enum _ShareChoice { thisError, today, last7Days, full }

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.event});

  final DiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _Header(event: event),
        const SizedBox(height: AppSpacing.lg),
        _SectionCard(
          title: 'Likely cause',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.cause.description, style: AppTypography.body),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Confidence: ${event.cause.confidence.label}',
                style: AppTypography.label.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'Where',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyValueRow('Screen', event.screen ?? '—'),
              _KeyValueRow('Component', event.component ?? '—'),
              if (event.operation != null) _KeyValueRow('Operation', event.operation!),
              if (event.failureStage != null) _KeyValueRow('Failure stage', event.failureStage!),
            ],
          ),
        ),
        if (event.evidence.isNotEmpty)
          _SectionCard(
            title: 'Evidence',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: event.evidence.map((e) => _BulletRow('${e.label}: ${e.value}')).toList(),
            ),
          ),
        if (event.breadcrumbs.isNotEmpty)
          _SectionCard(
            title: 'Recent activity',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: event.breadcrumbs
                  .map((b) => _BulletRow('${formatTime(b.timestamp)}  ${b.message}'))
                  .toList(),
            ),
          ),
        _TechnicalDetailsSection(event: event),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.event});

  final DiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(event.severity.icon, color: event.severity.colorOf(context), size: AppIconSize.emphasis),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: AppTypography.subheading),
              const SizedBox(height: 2),
              Text(
                '${formatRelativeDay(event.timestamp)}, ${formatTime(event.timestamp)}'
                '${event.occurrenceCount > 1 ? ' · Occurred ${event.occurrenceCount} times' : ''}',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(event.message, style: AppTypography.body),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: FulusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.label.copyWith(color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: AppTypography.body),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _TechnicalDetailsSection extends StatefulWidget {
  const _TechnicalDetailsSection({required this.event});

  final DiagnosticEvent event;

  @override
  State<_TechnicalDetailsSection> createState() => _TechnicalDetailsSectionState();
}

class _TechnicalDetailsSectionState extends State<_TechnicalDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return FulusCard(
      padding: EdgeInsets.zero,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Technical details',
                  style: AppTypography.label.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondaryOf(context)),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.sm),
              if (event.exceptionType != null) _KeyValueRow('Exception', event.exceptionType!),
              if (event.errorCode != null) _KeyValueRow('Error code', event.errorCode!),
              if (event.technicalContext.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                ...event.technicalContext.map((e) => _KeyValueRow(e.label, e.value)),
              ],
              if (event.stackTrace != null && event.stackTrace!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAltOf(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: SelectableText(
                    event.stackTrace!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
