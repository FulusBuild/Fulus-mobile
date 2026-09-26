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
      subtitle: 'Organize products for faster selling and stock management',
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
          return LayoutBuilder(
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
                          _CategoryOverview(count: categories.length),
                          const SizedBox(height: AppSpacing.xl),
                          const FulusSectionHeader(
                            title: 'Product categories',
                            subtitle: 'These categories appear as filters in Sell and Stock.',
                          ),
                          if (categories.isEmpty)
                            FulusCard(
                              child: FulusEmptyState(
                                icon: FulusIcons.sell,
                                headline: 'No categories yet',
                                body: 'Create your first category to make products easier to find while selling and managing stock.',
                                actionLabel: 'Add category',
                                onAction: () => _openAddSheet(context),
                              ),
                            )
                          else
                            FulusCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0; i < categories.length; i++) ...[
                                    _CategoryRow(category: categories[i]),
                                    if (i < categories.length - 1) const FulusListDivider(),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          FulusActionTile(
                            icon: FulusIcons.add,
                            title: 'Add category',
                            subtitle: 'Create a group for faster selling and stock management.',
                            onTap: () => _openAddSheet(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
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

class _CategoryOverview extends StatelessWidget {
  const _CategoryOverview({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selectedTintOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(FulusIcons.category, color: AppColors.primaryOf(context), size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'category' : 'categories'}',
                  style: AppTypography.subheading.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Keep your catalogue organized and easier to browse.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceAltOf(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(FulusIcons.sell, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (category.description != null && category.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    category.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New category', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Give products a simple grouping you can use across Stock and Sell.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
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
                child: FulusButton(label: 'Save category', loading: _saving, onPressed: _saving ? null : _save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
