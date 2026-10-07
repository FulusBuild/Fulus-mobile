import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/async_timeout.dart';
import '../../../../../domain/entities/location.dart';
import '../../../../../shared/widgets/widgets.dart';

final _locationsProvider = StreamProvider<List<Location>>((ref) {
  return ref
      .watch(locationRepositoryProvider)
      .watchLocations()
      .withFulusLoadingTimeout();
});

class ManageLocationsScreen extends ConsumerStatefulWidget {
  const ManageLocationsScreen({super.key});

  @override
  ConsumerState<ManageLocationsScreen> createState() => _ManageLocationsScreenState();
}

class _ManageLocationsScreenState extends ConsumerState<ManageLocationsScreen> {
  String? _switchingLocationId;

  Future<void> _setActive(BuildContext context, WidgetRef ref, Location location) async {
    if (_switchingLocationId != null) return;
    setState(() => _switchingLocationId = location.localId);
    try {
      await ref.read(switchActiveLocationProvider)(location.localId);
      // Rebuild every location-aware consumer from the new durable context.
      ref.invalidate(activeLocationIdProvider);
      ref.read(dataRefreshSignalProvider.notifier).state++;
      // Keep switching local-first/offline-safe, but reconcile the new location's
      // stock projection immediately when cloud sync is enabled and online.
      unawaited(ref.read(syncServiceProvider).refreshAfterContextChange());
      if (context.mounted) showFulusSnackbar(context, message: 'Now viewing ${location.name}.');
    } catch (error) {
      if (context.mounted) {
        showFulusSnackbar(context, message: error is StateError ? error.message : "Couldn't switch locations. Try again.");
      }
    } finally {
      if (mounted) setState(() => _switchingLocationId = null);
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
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(_locationsProvider);
    final activeIdAsync = ref.watch(activeLocationIdProvider);

    return FulusScreen(
      title: 'Locations',

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
          final activeStateReady = activeIdAsync.hasValue;
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = FulusLayout.columns(constraints.maxWidth, minTileWidth: 260, maxColumns: 3);
              final bottomInset = MediaQuery.viewPaddingOf(context).bottom + AppSpacing.xl;
              final addTile = Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: FulusActionTile(
                  icon: FulusIcons.add,
                  label: 'Add location',
                  onTap: _switchingLocationId == null ? () => _addLocation(context, ref) : null,
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
                            isSwitching: _switchingLocationId == location.localId,
                            onTap: !activeStateReady || isActive || _switchingLocationId != null
                                ? null
                                : () => _setActive(context, ref, location),
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
        loading: () => const _LocationsLoadingSkeleton(),
        error: (error, stackTrace) => FulusErrorState(
          message: "Couldn't load locations.",
          onRetry: () => ref.invalidate(_locationsProvider),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.isActive,
    required this.isSwitching,
    required this.onTap,
  });

  final Location location;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return FulusListRow(
      leading: Icon(
        FulusIcons.locations,
        color: isActive ? primary : AppColors.textSecondaryOf(context),
      ),
      title: Text(location.name),
      subtitle: Text(
        isSwitching ? 'Switching…' : isActive ? 'Active' : 'Tap to switch here',
      ),
      trailing: isSwitching
          ? SizedBox(
              width: AppTouchTarget.minimum,
              height: AppTouchTarget.minimum,
              child: Center(
                child: SizedBox(
                  width: AppIconSize.dense,
                  height: AppIconSize.dense,
                  child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                ),
              ),
            )
          : Icon(
              isActive ? FulusIcons.check : FulusIcons.chevronRight,
              color: isActive ? primary : AppColors.mutedOf(context),
            ),
      onTap: onTap,
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


class _LocationsLoadingSkeleton extends StatelessWidget {
  const _LocationsLoadingSkeleton();
  @override Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(AppSpacing.lg),
    itemCount: 4,
    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
    itemBuilder: (_, __) => const FulusListRowSkeleton(),
  );
}
