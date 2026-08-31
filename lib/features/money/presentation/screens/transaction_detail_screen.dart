import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/export/export_service.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/screens/photo_capture_screen.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/transaction_tile.dart';

/// One transaction, in full — every field a `MoneyTransaction` can
/// carry (payment method, counterparty, reference, note, line items
/// for a sale), the "transaction detail" every list row and breakdown
/// row in this feature ultimately leads to.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId, this.preloaded});

  final String transactionId;

  /// Passed via `GoRouterState.extra` by whichever list row was tapped,
  /// so this screen renders instantly without a loading flash for the
  /// by-far-most-common case (navigating in from a list that already
  /// held the object) — `getTransactionById` below is the fallback for
  /// a direct/deep link that only has the id.
  final MoneyTransaction? preloaded;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  late Future<MoneyTransaction?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : ref.read(moneyRepositoryProvider).getTransactionById(widget.transactionId);
  }

  /// Re-fetches after the receipt-photo section below changes
  /// something — `widget.preloaded` (if any) only ever seeds the
  /// first frame, so a stale copy of it is never reused past this
  /// point.
  void _reload() {
    setState(() {
      _future = ref.read(moneyRepositoryProvider).getTransactionById(widget.transactionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Transaction',
      body: FutureBuilder<MoneyTransaction?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load this transaction.",
              reassurance: 'Your record of it is safe — this is only about showing it right now.',
              onRetry: () => setState(() {
                _future = ref.read(moneyRepositoryProvider).getTransactionById(widget.transactionId);
              }),
            );
          }
          if (!snapshot.hasData) {
            return const _DetailSkeleton();
          }
          final t = snapshot.data;
          if (t == null) {
            return const FulusEmptyState(
              icon: Icons.receipt_long_outlined,
              headline: "This transaction couldn't be found.",
              body: 'It may have been part of an older period.',
            );
          }
          return _DetailBody(transaction: t, currencySymbol: currencySymbol, onChanged: _reload);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.transaction, required this.currencySymbol, required this.onChanged});

  final MoneyTransaction transaction;
  final String currencySymbol;

  /// Called after the receipt-photo section below successfully
  /// attaches or removes a photo, so the parent screen re-fetches
  /// rather than this widget silently going stale.
  final VoidCallback onChanged;

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final t = transaction;
    try {
      await ref.read(exportServiceProvider).export(
            format: ExportFormat.pdf,
            fileName: 'transaction-${t.id}',
            title: t.title,
            subtitle: '${formatRelativeDay(t.dateTime)} · ${formatTime(t.dateTime)}',
            headers: const ['Field', 'Value'],
            rows: [
              ['Amount', formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true)],
              if (t.paymentMethod != null) ['Payment method', t.paymentMethod!],
              if (t.counterpartyName != null) ['With', t.counterpartyName!],
              if (t.reference != null) ['Reference', t.reference!],
              if (t.note != null) ['Note', t.note!],
              for (final line in t.lineItems ?? const <String>[]) ['Item', line],
            ],
          );
    } catch (_) {
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't share this transaction right now.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    return ListView(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
                child: Icon(
                  moneyTransactionIcon(t),
                  size: AppIconSize.base,
                  color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true),
                style: AppTypography.display.copyWith(
                  color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                t.title,
                textAlign: TextAlign.center,
                style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatRelativeDay(t.dateTime)} · ${formatTime(t.dateTime)}',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
        ),
        FulusCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _DetailRow(label: 'Type', value: _typeLabel(t.type)),
              if (t.paymentMethod != null) const FulusListDivider(indented: false),
              if (t.paymentMethod != null) _DetailRow(label: 'Paid with', value: t.paymentMethod!),
              if (t.counterpartyName != null) const FulusListDivider(indented: false),
              if (t.counterpartyName != null)
                _DetailRow(label: t.isInflow ? 'From' : 'Paid to', value: t.counterpartyName!),
              if (t.reference != null) const FulusListDivider(indented: false),
              if (t.reference != null) _DetailRow(label: 'Reference', value: t.reference!),
            ],
          ),
        ),
        if (t.lineItems != null && t.lineItems!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          FulusSectionHeader(title: 'Items'),
          FulusCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < t.lineItems!.length; i++) ...[
                  if (i > 0) const FulusListDivider(indented: false),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: Text(t.lineItems![i], style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (t.type == MoneyTransactionType.expense) ...[
          const SizedBox(height: AppSpacing.lg),
          FulusSectionHeader(title: 'Receipt photo'),
          _ReceiptPhotoSection(transaction: t, onChanged: onChanged),
        ],
        if (t.note != null) ...[
          const SizedBox(height: AppSpacing.lg),
          FulusSectionHeader(title: 'Note'),
          FulusCard(
            child: Text(t.note!, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Share',
              icon: Icons.ios_share,
              variant: FulusButtonVariant.secondary,
              onPressed: () => _share(context, ref),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  static String _typeLabel(MoneyTransactionType type) {
    switch (type) {
      case MoneyTransactionType.saleIncome:
        return 'Sale';
      case MoneyTransactionType.manualIncome:
        return 'Other income';
      case MoneyTransactionType.customerRepayment:
        return 'Customer repayment';
      case MoneyTransactionType.expense:
        return 'Expense';
      case MoneyTransactionType.supplierPayment:
        return 'Supplier payment';
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          // Responsive UI audit — Flexible+ellipsis added. label is
          // always one of this screen's own fixed field names, but
          // value isn't always short: two of this row's call sites pass
          // counterpartyName (a customer/supplier's real name) and
          // reference (free-text), either of which can be long enough
          // to overflow against the label with no protection.
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          FulusSkeletonBox(width: 56, height: 56, borderRadius: BorderRadius.all(Radius.circular(28))),
          SizedBox(height: AppSpacing.md),
          FulusSkeletonBox(width: 160, height: 32),
          SizedBox(height: AppSpacing.sm),
          FulusSkeletonBox(width: 120, height: 16),
        ],
      ),
    );
  }
}

/// The after-the-fact counterpart to Add Expense's own capture flow —
/// gap-closure pass: "Receipt photo attachment on expenses." Only
/// ever rendered for a [MoneyTransactionType.expense] row (see the
/// `if` guard in [_DetailBody.build] above). Uses the same shared
/// `PhotoCaptureScreen` (shared/screens) Product Photo Capture uses.
class _ReceiptPhotoSection extends ConsumerWidget {
  const _ReceiptPhotoSection({required this.transaction, required this.onChanged});

  final MoneyTransaction transaction;
  final VoidCallback onChanged;

  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final path = await PhotoCaptureScreen.capture(context, title: 'Receipt photo');
    if (path == null) return;
    try {
      await ref.read(moneyRepositoryProvider).attachReceiptPhoto(
            transactionId: transaction.id,
            photoPath: path,
          );
      onChanged();
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't attach that photo. Please try again.");
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Remove receipt photo?',
      message: 'This only removes the photo — the expense itself stays exactly as recorded.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await ref.read(moneyRepositoryProvider).attachReceiptPhoto(
            transactionId: transaction.id,
            photoPath: null,
          );
      onChanged();
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't remove that photo. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = transaction.receiptPhotoPath;
    if (path == null) {
      return FulusCard(
        onTap: () => _capture(context, ref),
        child: Row(
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.primaryOf(context)),
            const SizedBox(width: AppSpacing.md),
            Text('Add photo of receipt',
                style: AppTypography.body.copyWith(color: AppColors.primaryOf(context))),
          ],
        ),
      );
    }
    return FulusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
            child: Image.file(File(path), width: double.infinity, height: 200, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: FulusButton(
                    label: 'Retake',
                    variant: FulusButtonVariant.secondary,
                    onPressed: () => _capture(context, ref),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FulusIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove',
                  onPressed: () => _remove(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
