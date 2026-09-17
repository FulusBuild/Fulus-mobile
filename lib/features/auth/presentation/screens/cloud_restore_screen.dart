import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ulid/ulid.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../data/remote/cloud_restore_coordinator.dart';
import '../../../../data/remote/endpoints/cloud_restore_api.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../shared/widgets/widgets.dart';

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
      connection.selectBusiness(businessId);

      setState(() => _status = 'Downloading your business data…');
      final snapshot = await CloudRestoreApi(ref.read(apiClientProvider))
          .fetchSnapshot(businessId: businessId);

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
      final result = await CloudRestoreCoordinator(ref.read(databaseProvider)).restore(
        snapshot: snapshot,
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: widget.ownerEmail,
        settings: settings,
      );
      if (result.totalRows == 0) {
        throw StateError('The cloud business has no restorable business data.');
      }

      final owner = await ref.read(authRepositoryProvider).restoreSession();
      if (owner == null || owner.id != ownerCloudUserId || !owner.isActive) {
        throw StateError('Restore completed without a valid local owner session.');
      }
      ref.read(sessionProvider.notifier).state = owner;

      await ref.read(syncConfigProvider).setEnabled(true);
      setState(() => _status = 'Reconciling with Fulus Cloud…');
      try {
        await ref.read(syncTriggersProvider).reconcileAfterRestore();
        connection.markSyncReady();
      } catch (_) {
        connection.clearSyncReady();
        rethrow;
      }

      if (!mounted) return;
      // Do not pop back into the authentication stack. A restore establishes
      // a real local session, so the router must be given the root location
      // explicitly and allowed to rebuild the authenticated shell.
      context.go('/');
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
          _status = 'Ready to restore your business.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('Bad state: ', '');
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
    return FulusScreen(
      title: 'Restore Fulus',
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your Fulus account is signed in. Restore your cloud business to this device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FulusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.ownerEmail,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textPrimaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FulusButton(
                          label: 'Restore my business',
                          loading: _busy,
                          onPressed: _busy ? null : _restore,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'This restores the business belonging to the signed-in Fulus account. Your existing local data is not merged with the cloud business.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
