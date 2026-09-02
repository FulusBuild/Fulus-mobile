import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';

/// Feature (customer management): one form, two jobs — create a new
/// customer ([existing] null) or edit an existing one ([existing] set,
/// every field pre-filled from it). A customer no longer has to be
/// standing at checkout before the business can create their profile,
/// and there's now a real way to fix a typo in one's phone number
/// without deleting and re-adding them.
///
/// Deliberately its own small file rather than living inside
/// customers_list_screen.dart or customer_profile_screen.dart — both
/// screens need it, and it's genuinely reusable as-is (nothing about it
/// is specific to either screen's own state).
class CustomerFormSheet extends ConsumerStatefulWidget {
  const CustomerFormSheet({super.key, this.existing});

  final Customer? existing;

  static Future<Customer?> show(BuildContext context, {Customer? existing}) {
    return showFulusBottomSheet<Customer?>(
      context: context,
      title: existing == null ? 'Add customer' : 'Edit customer',
      builder: (_) => CustomerFormSheet(existing: existing),
    );
  }

  @override
  ConsumerState<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<CustomerFormSheet> {
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
    final draft = CustomerDraft(
      name: name,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
    );
    try {
      final repo = ref.read(customerRepositoryProvider);
      final saved = widget.existing == null
          ? await repo.createCustomer(draft)
          : await repo.updateCustomer(widget.existing!.localId, draft);
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
        FulusTextField(label: 'Full name', controller: _nameController),
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
            label: widget.existing == null ? 'Add customer' : 'Save changes',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
