import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/product.dart';
import '../../../../domain/entities/stock_movement.dart';
import '../../../../shared/widgets/widgets.dart';

/// One entry in "what recently changed" — Product Design Bible Volume
/// 6's Product History: "every sale, stock in/out, transfer, and
/// adjustment... with a timestamp." No "who made it" here — a real gap,
/// not an omission: [StockMovement] has no actor/user field anywhere in
/// its schema (checked directly against the entity), so there is
/// nothing to attribute a row to yet. Flagged rather than guessed at.
class StockMovementTile extends StatelessWidget {
  const StockMovementTile({super.key, required this.movement, this.product, this.showProductName = false});

  final StockMovement movement;

  /// Only needed when [showProductName] is true (the location-wide feed
  /// on the overview screen and the full history screen); the
  /// product-detail screen's own history already has the product as
  /// context and passes null.
  final Product? product;
  final bool showProductName;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _presentation(context);
    return Semantics(
      button: false,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: FulusListRow(
          leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(
        showProductName && product != null
            ? '${_timestamp(movement.createdAt)} · ${product!.name}'
            : _timestamp(movement.createdAt),
      ),
      trailing: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          _quantityLabel(),
          style: AppTypography.body.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
        ),
      ),
    );
  }

  (IconData, String, Color) _presentation(BuildContext context) {
    switch (movement.movementType) {
      case StockMovementType.stockIn:
        return (FulusIcons.arrowDown, 'Stock in', AppColors.primaryOf(context));
      case StockMovementType.stockOut:
        return (FulusIcons.arrowUp, movement.reason ?? 'Stock out', AppColors.errorOf(context));
      case StockMovementType.adjustment:
        return (FulusIcons.settings, 'Adjusted', AppColors.warningOf(context));
      case StockMovementType.sale:
        return (FulusIcons.sell, 'Sold', AppColors.textPrimaryOf(context));
      case StockMovementType.transfer:
        return (FulusIcons.sync, 'Transferred', AppColors.infoOf(context));
    }
  }

  String _quantityLabel() {
    if (movement.movementType == StockMovementType.adjustment) {
      return '→ ${movement.newQuantity ?? '—'}';
    }
    final qty = movement.quantity;
    if (qty == null) return '—';
    final sign = movement.movementType == StockMovementType.stockIn ? '+' : '−';
    return '$sign$qty';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Same manual-formatting convention as receipt_engine.dart's
  /// `_formatDate`/`_formatLongDate` — no `intl` dependency in this
  /// project (checked directly against pubspec.yaml), so this follows
  /// the pattern that's already established rather than adding one.
  static String _timestamp(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:${dt.minute.toString().padLeft(2, '0')} $period';
    if (isToday) return 'Today, $time';
    return '${dt.day} ${_months[dt.month - 1]}, $time';
  }
}
