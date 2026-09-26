import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/location.dart';
import '../../../../../shared/widgets/widgets.dart';

final _locationsProvider = StreamProvider<List<Location>>((ref) {
  return ref.watch(locationRepositoryProvider).watchLocations();
});

class ManageLocationsScreen extends ConsumerWidget {
  const ManageLocationsScreen({super.key});

  Future<void> _setActive(BuildContext context, WidgetRef ref, Location location) async {
    try {
      await ref.read(switchActiveLocationProvider)(location.localId);
      // Rebuild every location-aware consumer from the new durable context.
      ref.invalidate(activeLocationIdProvider);
      ref.read(dataRefreshSignalProvider.notifier).state++;
      if (context.mounted) showFulusSnackbar(context, message: 'Now viewing ${location.name}.');
    } catch (error) {
      if (context.mounted) {
        showFulusSnackbar(context, message: error is StateError ? error.message : "Couldn't switch locations. Try again.");
      }
    }
  }

  Future<void> _addLocation(BuildContext context, WidgetRef ref) async {
    final name = await showFulusBottomSheet<String>(
      context: context,
      title: 'Add location',
      builder: (_) => const _AddLocationSheet(),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final created = await ref.read(locationRepositoryProvider).createLocation(LocationDraft(name: name.trim()));
      await _setActive(context, ref, created);
    } catch (_) {
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't add that location. Try again.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(_locationsProvider);
    final activeIdAsync = ref.watch(activeLocationIdProvider);

    return FulusScreen(
      title: 'Locations',
      subtitle: 'Choose where you are working',

      body: locationsAsync.when(
        data: (locations) {
          if (locations.isEmpty) {
            return FulusEmptyState(
              headline: 'No locations yet',
              body: 'Add your first location to start tracking sales, stock, and cash flow there.',
              actionLabel: 'Add location',
              onAction: () => _addLocation(context, ref),
            );
          }
          final activeId = activeIdAsync.value;
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = FulusLayout.columns(constraints.maxWidth, minTileWidth: 260, maxColumns: 3);
              final bottomInset = MediaQuery.viewPaddingOf(context).bottom + AppSpacing.xl;
              final addTile = Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: FulusActionTile(
                  icon: FulusIcons.add,
                  label: 'Add location',
                  subtitle: 'Create another place for this business',
                  onTap: () => _addLocation(context, ref),
                ),
              );
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: addTile),
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        childAspectRatio: columns == 1 ? 3.0 : 1.65,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final location = locations[index];
                          final isActive = location.localId == activeId;
                          return _LocationCard(
                            location: location,
                            isActive: isActive,
                            onTap: isActive ? null : () => _setActive(context, ref, location),
                          );
                        },
                        childCount: locations.length,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: FulusLoadingIndicator()),
        error: (error, stackTrace) => FulusErrorState(
          message: "Couldn't load locations.",
          onRetry: () => ref.invalidate(_locationsProvider),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.isActive, required this.onTap});
  final Location location;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      outlined: isActive,
      elevated: isActive,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? AppColors.selectedTintOf(context) : AppColors.surfaceAltOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(FulusIcons.locations, size: AppIconSize.base, color: isActive ? primary : AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(location.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.xs),
                if (isActive)
                  const FulusStatusPill(label: 'Active', icon: FulusIcons.check)
                else
                  Text('Tap to switch here', style: AppTypography.caption.copyWith(color: AppColors.mutedOf(context))),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(isActive ? FulusIcons.check : FulusIcons.chevronRight, color: isActive ? primary : AppColors.mutedOf(context)),
        ],
      ),
    );
  }
}

class _AddLocationSheet extends StatefulWidget {
  const _AddLocationSheet();
  @override
  State<_AddLocationSheet> createState() => _AddLocationSheetState();
}

class _AddLocationSheetState extends State<_AddLocationSheet> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FulusTextField(label: 'Location name', controller: _controller, hintText: 'e.g. Main Branch, Downtown'),
        const SizedBox(height: AppSpacing.lg),
        FulusButton(label: 'Add location', onPressed: () => Navigator.of(context).pop(_controller.text)),
      ],
    );
  }
}
