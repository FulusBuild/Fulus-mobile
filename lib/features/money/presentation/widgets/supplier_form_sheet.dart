import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/supplier.dart';
import '../../../../shared/widgets/widgets.dart';

/// Bug fix (suppliers gap-closure): the supplier-side mirror of
/// `CustomerFormSheet` — Volume 8, Decision 26's "a supplier's balance
/// works exactly like the customer credit book, mirrored" made literal
/// for creation/editing too, not just the balance itself.
/// `SupplierRepository.createSupplier` was already fully implemented
/// and reachable from `SupplierSyncHandler`; nothing in the UI ever
/// called it, so there was no way to add a supplier at all, and
/// therefore no supplier profile to ever reach. One form, two jobs —
/// create a new supplier ([existing] null) or edit one ([existing]
/// set, every field pre-filled).
class SupplierFormSheet extends ConsumerStatefulWidget {
  const SupplierFormSheet({super.key, this.existing});

  final Supplier? existing;

  static Future<Supplier?> show(BuildContext context, {Supplier? existing}) {
    return showFulusBottomSheet<Supplier?>(
      context: context,
      title: existing == null ? 'Add supplier' : 'Edit supplier',
      builder: (_) => SupplierFormSheet(existing: existing),
    );
  }

  @override
  ConsumerState<SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends ConsumerState<SupplierFormSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _emailController = TextEditingController(text: widget.existing?.email ?? '');
  late final _addressController = TextEditingController(text: widget.existing?.address ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = SupplierDraft(
      name: name,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
    );
    try {
      final repo = ref.read(supplierRepositoryProvider);
      final saved = widget.existing == null
          ? await repo.createSupplier(draft)
          : await repo.updateSupplier(widget.existing!.localId, draft);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save — try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
          const SizedBox(height: AppSpacing.sm),
        ],
        FulusTextField(label: 'Supplier name', controller: _nameController),
        const SizedBox(height: AppSpacing.sm),
        FulusTextField(label: 'Phone (optional)', controller: _phoneController, keyboardType: TextInputType.phone),
        const SizedBox(height: AppSpacing.sm),
        FulusTextField(
          label: 'Email (optional)',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: AppSpacing.sm),
        FulusTextField(label: 'Address (optional)', controller: _addressController),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FulusButton(
            label: widget.existing == null ? 'Add supplier' : 'Save changes',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
