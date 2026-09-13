import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/category.dart';
import '../../../../shared/widgets/widgets.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  late final Stream<List<Category>> _categoriesStream =
      ref.read(categoryRepositoryProvider).watchCategories();

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Categories',
      applyPadding: false,
      body: StreamBuilder<List<Category>>(
        stream: _categoriesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load categories.",
              reassurance: 'Your products are still safe on this device.',
              onRetry: () => setState(() {}),
            );
          }
          if (!snapshot.hasData) return const FulusLoadingIndicator();

          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return FulusEmptyState(
              icon: Icons.sell_outlined,
              headline: 'No categories yet.',
              body: 'Categories help organize Stock and appear as chips in Sell.',
              actionLabel: 'Add category',
              onAction: () => _openAddSheet(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final category = categories[i];
              return FulusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    if (category.description != null && category.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          category.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddSheet(context),
        tooltip: 'Add category',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddCategorySheet(),
    );
  }
}

class _AddCategorySheet extends ConsumerStatefulWidget {
  const _AddCategorySheet();

  @override
  ConsumerState<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends ConsumerState<_AddCategorySheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(categoryRepositoryProvider).createCategory(
            CategoryDraft(
              name: name,
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save this category. Please try again.";
        });
      }
    }
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
          Text('New category', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
            const SizedBox(height: AppSpacing.sm),
          ],
          FulusTextField(label: 'Name', controller: _nameController),
          const SizedBox(height: AppSpacing.sm),
          FulusTextField(label: 'Description (optional)', controller: _descriptionController),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FulusButton(label: 'Save', loading: _saving, onPressed: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}
