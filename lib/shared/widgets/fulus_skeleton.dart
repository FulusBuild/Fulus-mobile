import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Quiet, branded skeleton primitive. It uses a soft pulse rather than a
/// noisy shimmer so loading feels intentional and the eventual content does
/// not appear to jump in from a different visual language.
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
    duration: const Duration(milliseconds: 1050),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween(begin: 0.38, end: 0.82).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
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

/// Prevents fast screens from flashing a loading treatment for a frame or
/// two. When a load really takes time, the skeleton fades in instead of
/// appearing as a hard cut.
class FulusDelayedSkeleton extends StatefulWidget {
  const FulusDelayedSkeleton({super.key, required this.skeleton, this.threshold = const Duration(milliseconds: 280)});

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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _show ? KeyedSubtree(key: const ValueKey('skeleton'), child: widget.skeleton) : const SizedBox(key: ValueKey('empty')),
    );
  }
}

/// Branded indeterminate loading treatment for screens where a skeleton does
/// not make sense. The mark and progress ring give the wait a clear Fulus
/// identity instead of the generic standalone Material spinner.
class FulusLoadingIndicator extends StatefulWidget {
  const FulusLoadingIndicator({super.key, this.label = 'Loading'});
  final String label;

  @override
  State<FulusLoadingIndicator> createState() => _FulusLoadingIndicatorState();
}

class _FulusLoadingIndicatorState extends State<FulusLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.rotate(
              angle: _controller.value * 6.283185307,
              child: child,
            ),
            child: Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.selectedTintOf(context),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primaryOf(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.label,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ),
    );
  }
}
