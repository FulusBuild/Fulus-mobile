import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/printer_device.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Gap fix — Volume 11's "Pairing, testing, and unpairing a receipt
/// printer" and Volume 3's onboarding Printer Setup screen both had no
/// UI anywhere, despite a complete device-services layer underneath
/// (PrinterRepository, PrinterDiscoveryService, ReceiptPrinterService,
/// full ESC/POS command building). This screen is that missing UI, and
/// is what makes ReceiptPreviewSheet's Print button (see that file's
/// own updated header comment) able to do something real instead of
/// showing "coming soon."
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FulusSectionHeader(title: 'Paired printers'),
          Expanded(
            child: StreamBuilder<List<PairedPrinter>>(
              stream: ref.watch(printerRepositoryProvider).watchPaired(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const FulusLoadingIndicator();
                }
                final printers = snapshot.data!;
                if (printers.isEmpty) {
                  return FulusEmptyState(
                    icon: Icons.print_disabled_outlined,
                    headline: 'No printer paired yet.',
                    body: 'Printing is optional — Fulus works fully without one. '
                        'Pair one below when you\'re ready.',
                  );
                }
                return ListView(
                  children: [for (final p in printers) _PairedPrinterTile(printer: p)],
                );
              },
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Find a printer',
              onPressed: () => _openFindPrinterSheet(context),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FulusCard(
        child: Row(
          children: [
            Icon(
              printer.transport == PrinterTransport.bluetooth ? Icons.bluetooth : Icons.usb,
              color: AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(printer.name, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600)),
                  if (printer.isDefault)
                    Text('Default', style: AppTypography.caption.copyWith(color: AppColors.primaryOf(context))),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handle(context, ref, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'test', child: Text('Test print')),
                if (!printer.isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
                const PopupMenuItem(value: 'unpair', child: Text('Unpair')),
              ],
            ),
          ],
        ),
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

    // Nice-to-have gap closure — Volume 3 Decision 8's primer. USB has
    // no permission_handler permission to prime for (see
    // usb_receipt_printer.dart's own doc comment on why), so this only
    // applies to the Bluetooth branch, and only when access isn't
    // already granted from a previous pairing.
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
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Find a printer', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FulusButton(
                  label: 'Bluetooth',
                  variant: FulusButtonVariant.secondary,
                  onPressed: () => _scan(true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FulusButton(
                  label: 'USB',
                  variant: FulusButtonVariant.secondary,
                  onPressed: () => _scan(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_future != null)
            SizedBox(
              height: 240,
              child: FutureBuilder<List<PrinterDevice>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) {
                    final message = snap.error is DeviceFailure ? (snap.error as DeviceFailure).message : "Couldn't scan.";
                    return FulusErrorState(message: message);
                  }
                  if (!snap.hasData) return const FulusLoadingIndicator();
                  final devices = snap.data!;
                  if (devices.isEmpty) {
                    return FulusEmptyState(
                      icon: Icons.print_disabled_outlined,
                      headline: 'No printers found.',
                      body: 'For Bluetooth, pair the printer in your phone\'s Bluetooth '
                          'settings first, then try again here.',
                    );
                  }
                  return ListView(
                    children: [
                      for (final device in devices)
                        FulusListRow(
                          leading: const Icon(Icons.print_outlined),
                          title: Text(device.name),
                          subtitle: Text(device.address),
                          onTap: () => _pair(context, device),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
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
