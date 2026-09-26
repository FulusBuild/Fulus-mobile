import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_transaction.dart';
import '../utils/money_format.dart';

/// The type/category icon for a [MoneyTransaction] — shared between
/// this tile and the transaction detail screen's own header, so a
/// transaction shows the identical glyph everywhere it appears.
IconData moneyTransactionIcon(MoneyTransaction t) {
  switch (t.type) {
    case MoneyTransactionType.saleIncome:
      return FulusIcons.sell;
    case MoneyTransactionType.manualIncome:
      return FulusIcons.add;
    case MoneyTransactionType.customerRepayment:
      return FulusIcons.person;
    case MoneyTransactionType.supplierPayment:
      return FulusIcons.stock;
    case MoneyTransactionType.expense:
      switch (t.category) {
        case 'Rent':
          return FulusIcons.home;
        case 'Wages':
          return FulusIcons.customers;
        case 'Utilities':
          return FulusIcons.settings;
        case 'Transport':
          return FulusIcons.stock;
        default:
          return FulusIcons.receipt;
      }
  }
}

/// One row in the Cash Flow feed — Recent Transactions, Money History,
/// and (as a read-only header) Transaction Detail all build on this
/// same tile so a transaction looks identical everywhere it appears.
class MoneyTransactionTile extends StatelessWidget {
  const MoneyTransactionTile({
    super.key,
    required this.transaction,
    required this.currencySymbol,
    this.showDate = true,
    this.onTap,
  });

  final MoneyTransaction transaction;
  final String currencySymbol;
  final bool showDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final timeLabel = formatTime(t.dateTime);
    final subtitleParts = <String>[
      if (showDate) formatRelativeDay(t.dateTime),
      timeLabel,
      if (t.paymentMethod != null) t.paymentMethod!,
    ];

    return Semantics(
      button: onTap != null,
      label: '${t.title}. ${formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true)}. ${subtitleParts.join(', ')}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: FulusListRow(
          leading: t.type == MoneyTransactionType.saleIncome
          ? _SaleProductThumbnail(saleId: t.id.substring('sale-'.length))
          : Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
              child: Center(
                child: Icon(
                  moneyTransactionIcon(t),
                  size: AppIconSize.compact,
                  color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
                ),
              ),
            ),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true),
        style: AppTypography.body.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
          color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
        ),
      ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Resolves the products behind a sale and uses the first available local
/// product photo. This deliberately keeps the MoneyTransaction model lean:
/// product photos are device-local and are presentation-only data, while the
/// sale transaction itself remains the shared cash-flow model.
class _SaleProductThumbnail extends ConsumerWidget {
  const _SaleProductThumbnail({required this.saleId});

  final String saleId;

  Future<String?> _loadPhoto(WidgetRef ref) async {
    final sale = await ref.read(saleRepositoryProvider).getSaleByLocalId(saleId);
    if (sale == null) return null;

    for (final item in sale.items) {
      final productId = item.productLocalId;
      if (productId == null) continue;
      final product = await ref.read(productRepositoryProvider).getProductById(
            productId,
            locationId: sale.locationId,
          );
      final photoPath = product?.product.photoPath;
      if (photoPath != null && photoPath.trim().isNotEmpty) return photoPath;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: _loadPhoto(ref),
      builder: (context, snapshot) {
        final path = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceAltOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: path == null
                ? Icon(
                    FulusIcons.sell,
                    size: AppIconSize.compact,
                    color: AppColors.primaryOf(context),
                  )
                : Image.file(
                    File(path),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      FulusIcons.sell,
                      size: AppIconSize.compact,
                      color: AppColors.primaryOf(context),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
