import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Base shimmering block every skeleton shape below is built from — no
/// external shimmer package added (foundation brief: avoid new
/// dependencies unless genuinely necessary), just a looping opacity
/// pulse on a rounded rect, which reads as "loading" without the more
/// elaborate diagonal-sweep shimmer some packages provide.
///
/// [width]/[height] are nullable and unset by default — when this box
/// sits inside a parent that already gives it a tight size (e.g. an
/// [AspectRatio], as [FulusCardSkeleton]'s image slot does below), leave
/// them unset so the box fills exactly what it's given rather than
/// fighting that constraint with its own fixed size.
class FulusSkeletonBox extends StatefulWidget {
  const FulusSkeletonBox({super.key, this.width, this.height, this.borderRadius});

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<FulusSkeletonBox> createState() => _FulusSkeletonBoxState();
}

class _FulusSkeletonBoxState extends State<FulusSkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween(begin: 0.4, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceAltOf(context);
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: widget.borderRadius ?? BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
    );
  }
}

/// Mirrors `FulusListRow`'s own leading/title/subtitle/trailing slots —
/// "a skeleton always mirrors the real layout it's about to become"
/// (5.18).
class FulusListRowSkeleton extends StatelessWidget {
  const FulusListRowSkeleton({super.key, this.hasLeading = true, this.hasSubtitle = true});
  final bool hasLeading;
  final bool hasSubtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (hasLeading) ...[
            FulusSkeletonBox(width: 40, height: 40, borderRadius: BorderRadius.circular(AppRadius.sm)),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const FulusSkeletonBox(width: 160, height: 14),
                if (hasSubtitle) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const FulusSkeletonBox(width: 100, height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Product-card-shaped skeleton — square image slot, two text lines.
class FulusCardSkeleton extends StatelessWidget {
  const FulusCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: FulusSkeletonBox(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          const SizedBox(height: AppSpacing.sm),
          const FulusSkeletonBox(width: 100, height: 14),
          const SizedBox(height: AppSpacing.xs),
          const FulusSkeletonBox(width: 60, height: 12),
        ],
      ),
    );
  }
}

/// Stat-card-shaped skeleton — label line, big value line.
class FulusStatCardSkeleton extends StatelessWidget {
  const FulusStatCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusSkeletonBox(width: 80, height: 12),
          SizedBox(height: AppSpacing.sm),
          FulusSkeletonBox(width: 70, height: 22),
        ],
      ),
    );
  }
}

/// Delays showing [skeleton] until [threshold] has elapsed, per 5.18's
/// "appears only past ~400ms... so a fast response never flashes a
/// skeleton the user barely perceives." Wrap any of the skeleton shapes
/// above in this rather than showing them immediately when a load
/// starts.
class FulusDelayedSkeleton extends StatefulWidget {
  const FulusDelayedSkeleton({super.key, required this.skeleton, this.threshold = const Duration(milliseconds: 400)});

  final Widget skeleton;
  final Duration threshold;

  @override
  State<FulusDelayedSkeleton> createState() => _FulusDelayedSkeletonState();
}

class _FulusDelayedSkeletonState extends State<FulusDelayedSkeleton> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.threshold, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _show ? widget.skeleton : const SizedBox.shrink();
  }
}

/// Genuinely indeterminate wait, no layout to preview — 5.10's other
/// loading treatment, for cases the skeleton shapes above don't fit.
/// "Never mixed with a spinner" on the same screen as a skeleton
/// (5.18) — pick one per screen, not both.
class FulusLoadingIndicator extends StatelessWidget {
  const FulusLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: AppColors.primaryOf(context)));
  }
}
