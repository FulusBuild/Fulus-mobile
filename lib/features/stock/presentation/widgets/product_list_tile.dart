import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';

class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.item,
    required this.category,
    required this.onTap,
  });

  final ProductWithStock item;
  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final outOfStock = product.tracksStock && item.currentStock <= 0;
    final statusColor = outOfStock
        ? AppColors.errorOf(context)
        : item.isLowStock
            ? AppColors.warningOf(context)
            : AppColors.primaryOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: '${product.name}, ${item.currentStock} ${product.unit}',
        child: FulusListRow(
        onTap: null,
        leading: _Thumbnail(name: product.name, photoPath: product.photoPath),
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [category?.name ?? 'Uncategorized', formatMoney(product.sellingPrice)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: product.tracksStock
            ? Container(
                constraints: const BoxConstraints(minWidth: 64),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: statusColor.withValues(alpha: 0.14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${item.currentStock}',
                      style: AppTypography.body.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(product.unit, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                  ],
                ),
              )
            : Text('—', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.name, required this.photoPath});
  final String name;
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.selectedTintOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: photoPath == null
            ? Text(initial, style: AppTypography.buttonLabel.copyWith(color: AppColors.primaryOf(context)))
            : Image.file(
                File(photoPath!),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (context, error, stackTrace) => Text(
                  initial,
                  style: AppTypography.buttonLabel.copyWith(color: AppColors.primaryOf(context)),
                ),
              ),
      ),
    );
  }
}
