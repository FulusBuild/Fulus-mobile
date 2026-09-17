import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';

/// Customer selection stays inside checkout so a cashier never has to leave
/// the sale flow just to attach a customer.
class CustomerPickerSheet extends ConsumerStatefulWidget {
  const CustomerPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    final cubit = context.read<CartCubit>();
    return showFulusBottomSheet(
      context: context,
      title: 'Select customer',
      builder: (_) => BlocProvider.value(value: cubit, child: const CustomerPickerSheet()),
    );
  }

  @override
  ConsumerState<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<CustomerPickerSheet> {
  late final Stream<List<Customer>> _customersStream =
      ref.read(customerRepositoryProvider).watchCustomers();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartCubit = context.read<CartCubit>();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FulusSearchField(
            controller: _searchController,
            hintText: 'Search customer by name or phone',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusCard(
            padding: EdgeInsets.zero,
            child: FulusListRow(
              leading: Icon(FulusIcons.person, color: AppColors.textSecondaryOf(context)),
              title: const Text('Walk-in customer'),
              subtitle: const Text('No customer details needed'),
              onTap: () {
                cartCubit.setCustomer(null);
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: _customersStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const FulusLoadingIndicator();
                }
                final all = snapshot.data!;
                final query = _query.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? all
                    : all
                        .where((c) =>
                            c.name.toLowerCase().contains(query) ||
                            (c.phone?.toLowerCase().contains(query) ?? false))
                        .toList();
                if (filtered.isEmpty) {
                  return FulusEmptyState(
                    headline: query.isEmpty ? 'No customers yet' : 'No matches found',
                    body: query.isEmpty
                        ? 'Add a customer below when you need to keep their details.'
                        : 'Try a different name or phone number.',
                    icon: FulusIcons.person,
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, i) => const FulusListDivider(),
                  itemBuilder: (context, i) {
                    final customer = filtered[i];
                    return FulusListRow(
                      leading: Icon(FulusIcons.person, color: AppColors.textSecondaryOf(context)),
                      title: Text(customer.name),
                      subtitle: customer.phone == null ? null : Text(customer.phone!),
                      onTap: () {
                        cartCubit.setCustomer(customer);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusButton(
            label: 'Add customer',
            variant: FulusButtonVariant.secondary,
            icon: FulusIcons.person,
            onPressed: () => _addNewCustomer(context, cartCubit),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewCustomer(BuildContext context, CartCubit cartCubit) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add customer'),
        scrollable: true,
        content: FulusTextField(
          label: 'Customer name',
          controller: controller,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FulusButton(
            label: 'Add customer',
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await cartCubit.createAndSetWalkInCustomer(name);
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't add that customer.");
      }
    }
  }
}
