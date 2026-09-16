import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Compact search surface shared by catalog-style screens.
///
/// The widget owns its controller only when the caller does not provide one.
/// That keeps clear-button state reactive without taking ownership away from
/// screens that need to coordinate search state themselves.
class FulusSearchField extends StatefulWidget {
  const FulusSearchField({
    super.key,
    this.controller,
    this.hintText = 'Search…',
    this.onChanged,
    this.onClear,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  State<FulusSearchField> createState() => _FulusSearchFieldState();
}

class _FulusSearchFieldState extends State<FulusSearchField> {
  late TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(FulusSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onTextChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final secondary = AppColors.textSecondaryOf(context);
    final divider = AppColors.dividerOf(context);

    return SizedBox(
      height: AppTouchTarget.minimum,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimaryOf(context),
          fontWeight: FontWeight.w500,
        ),
        cursorColor: primary,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTypography.body.copyWith(color: secondary),
          filled: true,
          fillColor: AppColors.surfaceAltOf(context),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: AppIconSize.base,
            color: secondary,
          ),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  color: secondary,
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                    widget.onClear?.call();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: divider.withValues(alpha: 0.55)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: divider.withValues(alpha: 0.55)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
      ),
    );
  }
}
