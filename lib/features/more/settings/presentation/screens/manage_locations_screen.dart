import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/location.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Every location this business has — synced down from a desktop
/// companion (`LocationRepository.syncFromServer`) or created directly
/// from this screen. Feature-local (not `app/providers.dart`) since
/// nothing outside this screen needs the full list — every other
/// feature only ever needs the one *active* location
/// (`activeLocationIdProvider`).
final _locationsProvider = StreamProvider<List<Location>>((ref) {
  return ref.watch(locationRepositoryProvider).watchLocations();
});

/// Volume 6/Decision 21 made mobile-side location creation real: a
/// business isn't limited to whatever a desktop companion set up (or,
/// for a mobile-only business, to the one location silently seeded at
/// onboarding — `ResolveActiveLocation`). Owner-facing, reached from
/// More → Locations, matching this screen's siblings in the same list
/// (Employees, Reports, Backup — none of which gate on role at this
/// screen's level either; see `_MoreScreen`, app/router.dart).
///
/// Kept deliberately simple, matching Decision 21's own progressive-
/// disclosure spirit: a flat list, a name-only "Add Location" sheet,
/// tap-a-row-to-switch — no address/phone/hours fields, since
/// `Location` itself has none (location.dart's own doc comment: "a
/// thin entity, name is the only catalog field").
class ManageLocationsScreen extends ConsumerWidget {
  const ManageLocationsScreen({super.key});

  Future<void> _setActive(BuildContext context, WidgetRef ref, Location location) async {
    await ref.read(authRepositoryProvider).setActiveLocationId(location.localId);
    // Every other feature's "which location" question funnels through
    // this one provider (Sell/Stock/Money) — invalidating it here is
    // what actually makes a switch on this screen take effect
    // elsewhere, immediately, without an app restart.
    ref.invalidate(activeLocationIdProvider);
    if (context.mounted) {
      showFulusSnackbar(context, message: 'Now viewing ${location.name}.');
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
      final created = await ref.read(locationRepositoryProvider).createLocation(
            LocationDraft(name: name.trim()),
          );
      // A newly added second (or later) location is the natural moment
      // to switch to it — an owner adding a location almost always
      // means they're about to start using it, not admiring it from
      // the first location's point of view.
      await _setActive(context, ref, created);
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't add that location. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(_locationsProvider);
    final activeIdAsync = ref.watch(activeLocationIdProvider);

    return FulusScreen(
      title: 'Locations',
      applyPadding: false,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addLocation(context, ref),
        child: const Icon(Icons.add),
      ),
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
          final activeId = activeIdAsync.valueOrNull;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: locations.length,
            separatorBuilder: (_, __) => const FulusListDivider(indented: false),
            itemBuilder: (context, index) {
              final location = locations[index];
              final isActive = location.localId == activeId;
              return FulusListRow(
                title: Text(location.name),
                subtitle: isActive ? const Text('Active') : null,
                leading: Icon(
                  Icons.storefront_outlined,
                  color: isActive ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
                ),
                trailing: isActive
                    ? Icon(Icons.check_circle, color: AppColors.primaryOf(context))
                    : null,
                onTap: isActive ? null : () => _setActive(context, ref, location),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => FulusErrorState(
          message: "Couldn't load locations.",
          onRetry: () => ref.invalidate(_locationsProvider),
        ),
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
        FulusTextField(
          label: 'Location name',
          controller: _controller,
          hintText: 'e.g. Main Branch, Downtown',
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusButton(
          label: 'Add location',
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}
