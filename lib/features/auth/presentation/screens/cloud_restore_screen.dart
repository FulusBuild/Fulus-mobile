import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../data/remote/cloud_restore_coordinator.dart';
import '../../../../data/remote/endpoints/cloud_restore_api.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../sync/sync_user_message.dart';
import '../../../../sync/sync_execution_lease.dart';

/// Restores a Fulus installation from the user's single Fulus Cloud business.
///
/// Authentication is completed by [FulusAccountScreen] before this screen is
/// opened. This screen deliberately owns only the restore operation; it never
/// asks for the cloud credentials a second time.
class CloudRestoreScreen extends ConsumerStatefulWidget {
  const CloudRestoreScreen({super.key, required this.ownerEmail});

  final String ownerEmail;

  @override
  ConsumerState<CloudRestoreScreen> createState() => _CloudRestoreScreenState();
}

class _CloudRestoreScreenState extends ConsumerState<CloudRestoreScreen> {
  bool _busy = false;
  bool _restoreGateArmed = false;
  String? _error;
  String _status = 'Ready to restore your business.';

  BusinessSettingsResponseDto _settingsFromSnapshot(Map<String, dynamic> snapshot) {
    final business = snapshot['business'];
    if (business is! Map) {
      throw const FormatException('Restore snapshot did not contain business settings.');
    }
    final data = Map<String, dynamic>.from(business);
    final businessId = data['id']?.toString();
    final businessName = data['name']?.toString().trim();
    if (businessId == null || businessId.isEmpty || businessName == null || businessName.isEmpty) {
      throw const FormatException('Restore snapshot contained incomplete business settings.');
    }

    final currencyCode = data['currency_code']?.toString().toUpperCase();
    final currencySymbol = switch (currencyCode) {
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currencyCode ?? '₦',
    };

    return BusinessSettingsResponseDto(
      id: businessId,
      businessName: businessName,
      vatEnabled: data['vat_enabled'] == true,
      vatRate: data['vat_rate'] is num ? (data['vat_rate'] as num).toDouble() : 0,
      currencySymbol: currencySymbol,
      address: data['address']?.toString(),
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      tin: data['tin']?.toString(),
      receiptFooter: data['receipt_footer']?.toString(),
    );
  }

  Future<void> _restore() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Finding your business…';
    });

    try {
      // FulusAccountScreen has already authenticated this exact account and
      // stored its access/refresh credentials in ApiClient. Reusing that
      // session prevents duplicate credential entry and, importantly, keeps
      // authentication separate from the destructive local restore step.
      final connection = ref.read(fulusConnectionStateProvider);
      connection.markSessionAuthenticated();
      await connection.refresh();

      final active = connection.membershipContext?.memberships
              .where((membership) => membership.status == 'active')
              .toList(growable: false) ??
          const [];

      if (active.isEmpty) {
        throw StateError('This cloud account is not linked to an active Fulus business.');
      }
      if (active.length > 1) {
        throw StateError('This cloud account has multiple business memberships. Please contact Fulus support.');
      }

      final businessId = active.single.businessId;
      await connection.selectBusiness(businessId);
      ref.read(syncServiceProvider).markNotReady();

      // A restore creates a new authoritative local dataset. Discard health
      // metadata from any previous dataset before reconciliation so an old
      // stale cursor or blocked recovery state cannot poison this restore.
      await ref.read(syncStatusNotifierProvider).resetForAuthoritativeRestore(businessId);

      setState(() => _status = 'Downloading your business data…');
      final snapshot = await CloudRestoreApi(ref.read(apiClientProvider))
          .fetchSnapshot(businessId: businessId);
      final snapshotBoundary = snapshot['sync_boundary'];
      if (snapshotBoundary is! num || snapshotBoundary.toInt() < 0) {
        throw const FormatException(
          'Restore snapshot did not contain a valid sync boundary.',
        );
      }

      final ownerCloudUserId = (snapshot['membership'] is Map)
          ? (snapshot['membership'] as Map)['user_id']?.toString()
          : null;
      if (ownerCloudUserId == null || ownerCloudUserId.isEmpty) {
        throw StateError('Restore snapshot did not contain the authenticated owner identity.');
      }

      setState(() => _status = 'Preparing business settings…');
      final settings = _settingsFromSnapshot(snapshot);

      setState(() => _status = 'Registering this device…');
      await _registerDevice(connection);

      setState(() => _status = 'Restoring your business data…');
      final restoreLease = SyncExecutionLease(ref.read(databaseProvider));
      final result = await CloudRestoreCoordinator(
        ref.read(databaseProvider),
        executionLease: restoreLease,
      ).restore(
        snapshot: snapshot,
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: widget.ownerEmail,
        settings: settings,
        onProgress: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (result.totalRows == 0) {
        throw StateError('The cloud business has no restorable business data.');
      }

      setState(() => _status = 'Restoring your local session…');
      final owner = await ref.read(authRepositoryProvider).restoreSession();
      if (owner == null || owner.id != ownerCloudUserId || !owner.isActive) {
        throw StateError('Restore completed without a valid local owner session.');
      }
      ref.read(sessionProvider.notifier).state = owner;

      // Bind the local single-business database before enabling sync so
      // startup reconciliation cannot interpret this fresh restore as an
      // unbound installation or a different previously selected business.
      final syncPreferences = await SharedPreferences.getInstance();
      final persistedBusinessBinding = await syncPreferences.setString(
        'fulus_local_cloud_business_id',
        businessId,
      );
      if (!persistedBusinessBinding) {
        throw StateError(
          'Failed to persist the Cloud Sync business binding.',
        );
      }

      // The restore snapshot is a complete business image and carries the
      // exact change-feed boundary from the same server-side snapshot.
      // Persist that boundary before reconciliation so the first pull starts
      // strictly after the imported image.
      setState(() => _status = 'Preparing cloud sync…');
      final persistedBoundary = await syncPreferences.setInt(
        'fulus_sync_cursor_$businessId',
        snapshotBoundary.toInt(),
      );
      if (!persistedBoundary) {
        throw StateError(
          'Failed to persist the Cloud Sync restore snapshot boundary.',
        );
      }

      // Reserve the first reconciliation before enabling sync so the normal
      // readiness trigger cannot race the authoritative restore reconciliation.
      final syncService = ref.read(syncServiceProvider);
      _restoreGateArmed = true;
      await syncService.enableForRestore();

      // Restore is not complete when the local snapshot has been imported.
      // The restored database and the cloud cursor must be reconciled before
      // the app advertises the business as Sync Ready. SyncTriggers already
      // serializes a concurrent normal trigger with the restore reconciliation,
      // so the startup/restore race remains inside the sync boundary.
      setState(() => _status = 'Checking cloud sync…');
      try {
        await syncService.reconcileAfterRestore();
        _restoreGateArmed = false;
        syncService.markReady();
      } catch (error) {
        syncService.markReadinessError(error);
        rethrow;
      }

      setState(() => _status = 'Restore complete. Opening your business…');
      if (!mounted) return;

      // This screen was opened by FulusAccountScreen with a plain
      // MaterialPageRoute, not as a go_router route. Return a success result
      // so the account-entry route can also be removed and the reactive
      // ShellGate can reveal the restored business.
      Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      if (_restoreGateArmed) {
        ref.read(syncServiceProvider).cancelRestore();
        _restoreGateArmed = false;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncUserMessage(failure);
          _status = 'Ready to restore your business.';
        });
      }
    } catch (error) {
      if (_restoreGateArmed) {
        ref.read(syncServiceProvider).cancelRestore();
        _restoreGateArmed = false;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncUserMessage(error);
          _status = 'Ready to restore your business.';
        });
      }
    }
  }

  Future<void> _registerDevice(dynamic connection) async {
    final storage = ref.read(secureStorageProvider);
    final deviceId = await storage.ensureDeviceClientId(Ulid().toString());
    final package = await PackageInfo.fromPlatform();
    await connection.registerDevice(
      deviceClientId: deviceId,
      deviceName: 'Fulus Mobile',
      platform: Platform.operatingSystem,
      appVersion: package.version,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final muted = AppColors.textSecondaryOf(context);

    return FulusScreen(
      title: 'Restore Fulus',
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxxl,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontSize: 34,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your Fulus account is signed in. Restore your cloud business to this device.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: muted),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FulusCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.selectedTintOf(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          Icons.cloud_done_rounded,
                          color: primary,
                          size: AppIconSize.base,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signed-in account',
                              style: AppTypography.label.copyWith(color: muted),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              widget.ownerEmail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body.copyWith(
                                color: AppColors.textPrimaryOf(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FulusActionTile(
                  label: _busy ? 'Restoring your business…' : 'Restore my business',
                  subtitle: _busy
                      ? _status
                      : 'Bring your cloud business onto this device.',
                  icon: Icons.cloud_download_rounded,
                  onTap: _busy ? null : _restore,
                  trailing: _busy ? const FulusLoadingIndicator() : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  FulusCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: AppIconSize.compact,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTypography.caption.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: AppIconSize.dense,
                      color: muted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your existing local data is not merged with the cloud business. Keep Fulus open while the restore is in progress.',
                        textAlign: TextAlign.left,
                        style: AppTypography.caption.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
