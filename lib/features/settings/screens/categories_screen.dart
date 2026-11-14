import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/log_category.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';

/// Colour of a category: the user's choice, else a stable palette colour.
Color categoryColor(String name, List<LogCategory> categories) {
  final c = categories.where((c) => c.name == name).firstOrNull;
  return c != null ? Color(c.colorValue) : paletteFor(name);
}

/// Asks for a new category (name + colour), adds it and returns its name.
/// Returns the existing name if one with the same name already exists.
Future<String?> promptNewCategory(BuildContext context, WidgetRef ref) async {
  final result = await _CategoryDialog.show(context, title: 'New category');
  if (result == null) return null;
  final list = ref.read(logCategoriesProvider);
  final existing = list
      .where((c) => c.name.toLowerCase() == result.name.toLowerCase())
      .firstOrNull;
  if (existing != null) return existing.name;
  ref.read(logCategoriesProvider.notifier).state = [...list, result];
  return result.name;
}

/// Manage categories: add, rename (updates past entries), recolour, remove.
/// The same list is used by Log and by transaction details.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()));

  Future<void> _edit(BuildContext context, WidgetRef ref, LogCategory c) async {
    final result = await _CategoryDialog.show(
      context,
      title: 'Edit category',
      initial: c,
    );
    if (result == null) return;
    final list = ref.read(logCategoriesProvider);
    final clash =
        result.name != c.name &&
        list.any((x) => x.name.toLowerCase() == result.name.toLowerCase());
    if (clash) return;
    ref.read(logCategoriesProvider.notifier).state = [
      for (final x in list)
        if (x.name == c.name) result else x,
    ];
    if (result.name != c.name) {
      // Keep history consistent: past entries move to the new name.
      final db = ref.read(databaseProvider);
      await (db.update(db.transactions)
            ..where((t) => t.category.equals(c.name)))
          .write(TransactionsCompanion(category: Value(result.name)));
      await (db.update(db.transactions)..where(
            (t) => t.merchant.equals(c.name) & t.category.equals(result.name),
          ))
          .write(TransactionsCompanion(merchant: Value(result.name)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(logCategoriesProvider);
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Categories',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'Add category',
        onPressed: () => promptNewCategory(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.sm),
        children: [
          for (final c in list)
            ListTile(
              key: ValueKey('cat-${c.name}'),
              leading: ColorDot(Color(c.colorValue), size: 14),
              title: Text(c.name),
              onTap: () => _edit(context, ref, c),
              trailing: c.name == 'Other'
                  ? null
                  : IconButton(
                      tooltip: 'Remove ${c.name}',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () =>
                          ref.read(logCategoriesProvider.notifier).state = [
                            for (final x in list)
                              if (x.name != c.name) x,
                          ],
                    ),
            ),
          Padding(
            padding: const EdgeInsets.all(RiveroSpacing.lg),
            child: Text(
              'Removing a category keeps past entries as they are.',
              style: RiveroTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.title, this.initial});

  final String title;
  final LogCategory? initial;

  static Future<LogCategory?> show(
    BuildContext context, {
    required String title,
    LogCategory? initial,
  }) => showDialog<LogCategory>(
    context: context,
    builder: (_) => _CategoryDialog(title: title, initial: initial),
  );

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late int _color =
      widget.initial?.colorValue ?? RiveroColors.categorical.first.toARGB32();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('category-name'),
            controller: _name,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Rent, Pets, Gifts…',
              counterText: '',
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          Wrap(
            spacing: RiveroSpacing.sm,
            runSpacing: RiveroSpacing.sm,
            children: [
              for (final c in RiveroColors.categorical)
                GestureDetector(
                  onTap: () => setState(() => _color = c.toARGB32()),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 3,
                        color: _color == c.toARGB32()
                            ? RiveroColors.textPrimary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, LogCategory(name, _color));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
