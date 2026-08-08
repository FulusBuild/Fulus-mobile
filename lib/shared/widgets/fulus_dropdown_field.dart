import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'fulus_bottom_sheet.dart';

/// One option in a [FulusDropdownField].
class FulusDropdownOption<T> {
  const FulusDropdownOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Choosing one option from a short, known list — Component Library
/// 5.13: "Referenced elsewhere in this Bible's Screen Gallery before
/// this section existed to define it." Renders as a text-field-styled
/// trigger; opens an anchored menu for ≤5 short [options], or a
/// [showFulusBottomSheet] for more than 5 or for long labels — exactly
/// the size rule 5.13 states, so a caller doesn't have to pick the
/// right presentation itself. Refund destination, currency, and
/// category selectors should all build on this rather than a bespoke
/// dropdown per screen.
class FulusDropdownField<T> extends StatefulWidget {
  const FulusDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<FulusDropdownOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  State<FulusDropdownField<T>> createState() => _FulusDropdownFieldState<T>();
}

class _FulusDropdownFieldState<T> extends State<FulusDropdownField<T>> {
  final _fieldKey = GlobalKey();
  bool _open = false;

  String get _selectedLabel {
    final matches = widget.options.where((o) => o.value == widget.value);
    return matches.isEmpty ? '' : matches.first.label;
  }

  // "≤5 short options" per 5.13 — a rough proxy for "short": also
  // requires no label over ~18 characters, since a long label is the
  // other trigger 5.13 names for falling back to a sheet.
  bool get _useAnchoredMenu =>
      widget.options.length <= 5 && widget.options.every((o) => o.label.length <= 18);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: _fieldKey,
      onTap: () => _useAnchoredMenu ? _openAnchoredMenu(context) : _openSheet(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: AppMotion.standard,
            child: const Icon(Icons.expand_more),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        ),
        child: Text(
          _selectedLabel.isEmpty ? ' ' : _selectedLabel,
          style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
        ),
      ),
    );
  }

  Future<void> _openAnchoredMenu(BuildContext context) async {
    final button = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    setState(() => _open = true);
    final selected = await showMenu<T>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: button.size.width, maxWidth: button.size.width),
      items: [for (final o in widget.options) _menuItem(context, o)],
    );
    if (mounted) setState(() => _open = false);
    if (selected != null) widget.onChanged(selected);
  }

  PopupMenuItem<T> _menuItem(BuildContext context, FulusDropdownOption<T> o) {
    final selected = o.value == widget.value;
    return PopupMenuItem<T>(
      value: o.value,
      height: AppTouchTarget.minimum,
      child: Row(
        children: [
          Expanded(
            child: Text(
              o.label,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          // "Selected row: Primary/50 fill, Primary text, trailing
          // checkmark — same selected treatment as a Chip" (5.13). The
          // Primary/50 fill is left to the bottom-sheet variant below
          // (via ListTile.tileColor) — PopupMenuItem has no per-item
          // background color slot, so this variant relies on the
          // colored label + checkmark pair, which already satisfies
          // "never relies on color alone."
          if (selected) Icon(Icons.check, color: AppColors.primaryOf(context), size: AppIconSize.compact),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showFulusBottomSheet<T>(
      context: context,
      title: widget.label,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in widget.options)
            ListTile(
              title: Text(o.label),
              trailing: o.value == widget.value ? Icon(Icons.check, color: AppColors.primaryOf(sheetContext)) : null,
              tileColor: o.value == widget.value ? AppColors.selectedTintOf(sheetContext) : null,
              onTap: () => Navigator.of(sheetContext).pop(o.value),
            ),
        ],
      ),
    );
    if (selected != null) widget.onChanged(selected);
  }
}
