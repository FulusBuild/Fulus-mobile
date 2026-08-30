import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/category.dart';
import '../../../../shared/widgets/widgets.dart';

/// Gap fix: nothing anywhere in the app could create a category before
/// this — Add/Edit Product could only *select* one of whatever already
/// existed. `CategoryRepository` (createCategory, watchCategories) had
/// no caller anywhere.
///
/// List + create only, honestly — CategoryRepository has no update or
/// delete/archive method at all (checked directly; not a UI omission,
/// there's nothing to call). Renaming or removing a category is a real
/// remaining gap this screen doesn't claim to close.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  // Perf/correctness: created once here rather than inline in
  // StreamBuilder's `stream:` parameter — the same fix
  // sell_screen.dart already applies to this exact repository call.
  // Constructing it in build() instead would tear down and recreate
  // the underlying watch query (and briefly drop back to "no data")
  // on every rebuild of this screen, not just when categories
  // actually change.
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
          if (!snapshot.hasData) {
            return const FulusLoadingIndicator();
          }
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
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                    ),
                    if (category.description != null && category.description!.isNotEmpty)
                      Text(
                        category.description!,
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
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
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = "Couldn't save this category. Please try again.";
      });
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
