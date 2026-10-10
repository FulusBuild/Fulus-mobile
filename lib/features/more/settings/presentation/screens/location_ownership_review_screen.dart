import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/location.dart';
import '../../../../../data/remote/fulus_staff_access_api.dart';
import '../../../../../shared/widgets/widgets.dart';

final _ownershipReviewLocationsProvider = StreamProvider<List<Location>>((ref) {
  return ref.watch(locationRepositoryProvider).watchLocations();
});

class LocationOwnershipReviewScreen extends ConsumerStatefulWidget {
  const LocationOwnershipReviewScreen({super.key});

  @override
  ConsumerState<LocationOwnershipReviewScreen> createState() =>
      _LocationOwnershipReviewScreenState();
}

class _LocationOwnershipReviewScreenState
    extends ConsumerState<LocationOwnershipReviewScreen> {
  Future<List<LocationOwnershipReview>>? _reviewsFuture;
  String? _resolvingReviewId;

  Future<List<LocationOwnershipReview>> _loadReviews() async {
    final connection = ref.read(fulusConnectionStateProvider);
    final businessId = connection.selectedBusinessId;
    if (businessId == null || businessId.isEmpty) {
      throw StateError('Connect this device to a business before reviewing ownership.');
    }
    return await ref.read(fulusStaffAccessApiProvider).listLocationOwnershipReviews(
          businessId: businessId,
        );
  }

  void _reload() {
    setState(() => _reviewsFuture = _loadReviews());
  }

  @override
  void initState() {
    super.initState();
    _reviewsFuture = _loadReviews();
  }

  Future<void> _resolve(
    LocationOwnershipReview review,
    Location location,
  ) async {
    if (_resolvingReviewId != null) return;
    final businessId = ref.read(fulusConnectionStateProvider).selectedBusinessId;
    if (businessId == null || businessId.isEmpty) {
      showFulusSnackbar(context, message: 'Business connection is unavailable.');
      return;
    }
    setState(() => _resolvingReviewId = review.id);
    try {
      await ref.read(fulusStaffAccessApiProvider).resolveLocationOwnershipReview(
            businessId: businessId,
            reviewId: review.id,
            locationId: location.serverId ?? location.localId,
          );
      if (!mounted) return;
      showFulusSnackbar(
        context,
        message: '${review.displayEntityType} assigned to ${location.name}.',
      );
      setState(() => _reviewsFuture = _loadReviews());
      // The resolved row changes cloud ownership. Refresh local projections
      // only after the server confirms the transactional resolution.
      ref.read(dataRefreshSignalProvider.notifier).state++;
    } catch (error) {
      if (mounted) {
        showFulusSnackbar(
          context,
          message: error is StateError
              ? error.message
              : 'Could not resolve this record. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingReviewId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(_ownershipReviewLocationsProvider);
    final reviewsFuture = _reviewsFuture;

    return FulusScreen(
      title: 'Legacy ownership',
      body: reviewsFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<LocationOwnershipReview>>(
              future: reviewsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return FulusErrorState(
                    message: snapshot.error is StateError
                        ? (snapshot.error as StateError).message
                        : 'Could not load legacy ownership reviews. Owner or admin access is required.',
                    onRetry: _reload,
                  );
                }
                final reviews = snapshot.data ?? const <LocationOwnershipReview>[];
                if (reviews.isEmpty) {
                  return const FulusEmptyState(
                    icon: Icons.verified_outlined,
                    headline: 'No records need review',
                    body: 'All currently listed legacy product and customer ownership reviews are resolved.',
                  );
                }
                return locationsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => FulusErrorState(
                    message: 'Could not load locations. No ownership was changed.',
                    onRetry: () => ref.invalidate(_ownershipReviewLocationsProvider),
                  ),
                  data: (locations) {
                    if (locations.isEmpty) {
                      return const FulusEmptyState(
                        headline: 'No locations available',
                        body: 'Create or restore a business location before assigning legacy records.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final review = reviews[index];
                        final resolving = _resolvingReviewId == review.id;
                        return _OwnershipReviewCard(
                          review: review,
                          locations: locations,
                          resolving: resolving,
                          onResolve: (location) => _resolve(review, location),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _OwnershipReviewCard extends StatelessWidget {
  const _OwnershipReviewCard({
    required this.review,
    required this.locations,
    required this.resolving,
    required this.onResolve,
  });

  final LocationOwnershipReview review;
  final List<Location> locations;
  final bool resolving;
  final ValueChanged<Location> onResolve;

  @override
  Widget build(BuildContext context) {
    final candidates = review.candidateLocationIds.toSet();
    final cloudLocations = locations
        .where((location) => location.serverId != null && location.serverId!.isNotEmpty)
        .toList(growable: false);
    final suggested = cloudLocations
        .where((location) => candidates.contains(location.serverId))
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderOf(context)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                review.displayEntityType,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Record ID: ${review.entityId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (review.classification.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('Type: ${review.classification}'),
              ],
              if (review.reason.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(review.reason),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Choose the correct location. This action is explicit and cannot be inferred from history.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final location in cloudLocations)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: FulusListRow(
                    leading: Icon(
                      candidates.contains(location.serverId)
                          ? Icons.location_on_outlined
                          : Icons.place_outlined,
                    ),
                    title: Text(location.name),
                    subtitle: Text(
                      candidates.contains(location.localId)
                          ? 'Suggested by existing records'
                          : 'Assign to this location',
                    ),
                    trailing: resolving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: resolving ? null : () => _confirmAndResolve(context, location),
                  ),
                ),
              if (suggested.isEmpty)
                Text(
                  'No suggested location was found. Choose only if you know where this record belongs.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndResolve(BuildContext context, Location location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assign ownership?'),
        content: Text(
          'Assign this ${review.displayEntityType.toLowerCase()} to ${location.name}? '
          'Historical transactions will not be moved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed == true) onResolve(location);
  }
}
