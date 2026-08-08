import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Search bar — Component Library 5.6. Full pill radius, 48dp height,
/// "sits at the top of any screen with more than ~15 items." Filters
/// are Chips (5.2 — see `fulus_chip.dart`'s `FulusChip`), not a
/// separate component per the Bible; this widget only owns the text
/// input itself. Empty results are the caller's job, via
/// `fulus_empty_state.dart`'s `FulusEmptyState`.
///
/// A [StatefulWidget] (not stateless) specifically so the clear button
/// appears/disappears reactively as the user types, whether or not the
/// caller supplies its own [controller] — a stateless version would
/// only update its clear-button visibility when something above it
/// happens to rebuild, which isn't guaranteed on every keystroke.
class FulusSearchField extends StatefulWidget {
  const FulusSearchField({
    super.key,
    this.controller,
    this.hintText = 'Search…',
    this.onChanged,
    this.onClear,
    this.autofocus = false,
  });

  /// Optional — if omitted, this widget creates and owns its own.
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  State<FulusSearchField> createState() => _FulusSearchFieldState();
}

class _FulusSearchFieldState extends State<FulusSearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTouchTarget.minimum,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        autofocus: widget.autofocus,
        style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
        decoration: InputDecoration(
          hintText: widget.hintText,
          filled: true,
          fillColor: AppColors.surfaceAltOf(context),
          prefixIcon: Icon(Icons.search, size: AppIconSize.base, color: AppColors.textSecondaryOf(context)),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                    widget.onClear?.call();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          // Search bars aren't a labeled form field (5.7's "label
          // always visible" rule is for Forms & Inputs specifically) —
          // no floating label needed, overriding AppTheme's app-wide
          // InputDecorationTheme default of .always for this one field.
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
      ),
    );
  }
}
