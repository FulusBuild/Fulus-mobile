import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/printer_device.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Receipt-printer pairing, testing, and unpairing workspace.
///
/// The presentation stays separate from the printer services so the existing
/// discovery, pairing, test-print, and permission behavior remains unchanged.
class PrinterPairingScreen extends ConsumerStatefulWidget {
  const PrinterPairingScreen({super.key});

  @override
  ConsumerState<PrinterPairingScreen> createState() => _PrinterPairingScreenState();
}

class _PrinterPairingScreenState extends ConsumerState<PrinterPairingScreen> {
  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Printers',
      subtitle: 'Connect a receipt printer for optional paper receipts',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final inset = wide ? AppSpacing.lg : AppSpacing.sm;
          return ListView(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FulusCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.selectedTintOf(context),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Icon(Icons.print_outlined, color: AppColors.primaryOf(context), size: 28),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Receipt printing',
                                    style: AppTypography.subheading.copyWith(
                                      color: AppColors.textPrimaryOf(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Printing is optional. Your sales remain saved locally even when no printer is connected.',
                                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const FulusSectionHeader(
                        title: 'Paired printers',
                        subtitle: 'Manage the receipt printers available to this device',
                      ),
                      StreamBuilder<List<PairedPrinter>>(
                        stream: ref.watch(printerRepositoryProvider).watchPaired(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return FulusErrorState(
                              message: "Couldn't load paired printers.",
                              reassurance: 'Your sales and other business data are not affected.',
                              onRetry: () => setState(() {}),
                            );
                          }
                          if (!snapshot.hasData) return const FulusLoadingIndicator();

                          final printers = snapshot.data!;
                          if (printers.isEmpty) {
                            return FulusCard(
                              child: FulusEmptyState(
                                icon: Icons.print_disabled_outlined,
                                headline: 'No printer paired yet',
                                body: 'Pair a Bluetooth or USB receipt printer when you are ready. Fulus works fully without one.',
                                actionLabel: 'Find a printer',
                                onAction: () => _openFindPrinterSheet(context),
                              ),
                            );
                          }

                          return FulusCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < printers.length; i++) ...[
                                  _PairedPrinterTile(printer: printers[i]),
                                  if (i < printers.length - 1) const FulusListDivider(),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: wide ? null : double.infinity,
                        child: FulusButton(
                          label: 'Find a printer',
                          icon: Icons.search_outlined,
                          onPressed: () => _openFindPrinterSheet(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openFindPrinterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FindPrinterSheet(),
    );
  }
}

class _PairedPrinterTile extends ConsumerWidget {
  const _PairedPrinterTile({required this.printer});

  final PairedPrinter printer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transportIcon = printer.transport == PrinterTransport.bluetooth ? Icons.bluetooth : Icons.usb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceAltOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(transportIcon, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  printer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  printer.isDefault ? 'Default printer' : 'Available for receipts',
                  style: AppTypography.caption.copyWith(
                    color: printer.isDefault ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Printer actions',
            onSelected: (value) => _handle(context, ref, value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'test', child: Text('Test print')),
              if (!printer.isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
              const PopupMenuItem(value: 'unpair', child: Text('Unpair')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'test':
        try {
          await ref.read(receiptPrinterServiceProvider).testPrint(printer);
          if (context.mounted) showFulusSnackbar(context, message: 'Test print sent.');
        } on DeviceFailure catch (f) {
          if (context.mounted) showFulusSnackbar(context, message: f.message);
        }
      case 'default':
        await ref.read(printerRepositoryProvider).setDefault(printer.id);
      case 'unpair':
        final confirmed = await showFulusConfirmDialog(
          context,
          title: 'Unpair ${printer.name}?',
          message: 'You can pair it again later.',
          confirmLabel: 'Unpair',
        );
        if (confirmed) await ref.read(printerRepositoryProvider).unpair(printer.id);
    }
  }
}

class _FindPrinterSheet extends ConsumerStatefulWidget {
  const _FindPrinterSheet();

  @override
  ConsumerState<_FindPrinterSheet> createState() => _FindPrinterSheetState();
}

class _FindPrinterSheetState extends ConsumerState<_FindPrinterSheet> {
  Future<List<PrinterDevice>>? _future;

  Future<void> _scan(bool bluetooth) async {
    final discovery = ref.read(printerDiscoveryServiceProvider);

    if (bluetooth && !await discovery.hasBluetoothPermission) {
      if (!mounted) return;
      final proceed = await showFulusPermissionPrimer(
        context,
        icon: Icons.bluetooth,
        message: "We'll ask to use Bluetooth next — this lets us find and connect to your receipt printer.",
      );
      if (!proceed) return;
    }

    setState(() {
      _future = bluetooth ? discovery.scanBluetooth() : discovery.scanUsb();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: bottomInset + AppSpacing.lg,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 640;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Find a printer', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Choose how Fulus should discover your receipt printer.',
                              style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.print_outlined, color: AppColors.primaryOf(context)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (wide)
                    Row(
                      children: [
                        Expanded(child: _DiscoveryButton(label: 'Bluetooth', icon: Icons.bluetooth, onPressed: () => _scan(true))),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _DiscoveryButton(label: 'USB', icon: Icons.usb, onPressed: () => _scan(false))),
                      ],
                    )
                  else
                    Column(
                      children: [
                        SizedBox(width: double.infinity, child: _DiscoveryButton(label: 'Bluetooth', icon: Icons.bluetooth, onPressed: () => _scan(true))),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(width: double.infinity, child: _DiscoveryButton(label: 'USB', icon: Icons.usb, onPressed: () => _scan(false))),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (_future != null)
                    FulusCard(
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        height: 260,
                        child: FutureBuilder<List<PrinterDevice>>(
                          future: _future,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              final message = snap.error is DeviceFailure ? (snap.error as DeviceFailure).message : "Couldn't scan for printers.";
                              return FulusErrorState(message: message, reassurance: 'You can try another discovery method.');
                            }
                            if (!snap.hasData) return const FulusLoadingIndicator();
                            final devices = snap.data!;
                            if (devices.isEmpty) {
                              return FulusEmptyState(
                                icon: Icons.print_disabled_outlined,
                                headline: 'No printers found',
                                body: 'For Bluetooth, pair the printer in your phone\'s Bluetooth settings first, then try again here.',
                              );
                            }
                            return ListView.separated(
                              itemCount: devices.length,
                              separatorBuilder: (_, __) => const FulusListDivider(),
                              itemBuilder: (context, index) {
                                final device = devices[index];
                                return FulusListRow(
                                  leading: const Icon(Icons.print_outlined),
                                  title: Text(device.name),
                                  subtitle: Text(device.address),
                                  onTap: () => _pair(context, device),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pair(BuildContext context, PrinterDevice device) async {
    await ref.read(printerRepositoryProvider).pair(device);
    if (context.mounted) {
      Navigator.of(context).pop();
      showFulusSnackbar(context, message: '${device.name} paired.');
    }
  }
}

class _DiscoveryButton extends StatelessWidget {
  const _DiscoveryButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FulusButton(
      label: label,
      icon: icon,
      variant: FulusButtonVariant.secondary,
      onPressed: onPressed,
    );
  }
}
