import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Account types live on their own page so a long list never crowds Settings.
class AccountTypesScreen extends ConsumerWidget {
  const AccountTypesScreen({super.key});

  static const maxTypes = 100;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AccountTypesScreen()));

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New account type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'PPF, Forex card, Chit fund…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final current = ref.read(customAccountTypesProvider);
    if (current.length >= maxTypes ||
        current.any((t) => t.toLowerCase() == name.toLowerCase())) {
      return;
    }
    ref.read(customAccountTypesProvider.notifier).state = [...current, name];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(customAccountTypesProvider);
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Account types',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            tooltip: 'Add account type',
            onPressed: types.length >= maxTypes
                ? null
                : () => _add(context, ref),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: types.length,
        itemBuilder: (_, i) {
          final type = types[i];
          final builtIn = StandardAccountTypes.defaultList.contains(type);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: RiveroSpacing.xl,
            ),
            leading: Icon(
              StandardAccountTypes.getIcon(type),
              color: RiveroColors.textSecondary,
            ),
            title: Text(type),
            trailing: builtIn
                ? null
                : IconButton(
                    tooltip: 'Remove $type',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () =>
                        ref.read(customAccountTypesProvider.notifier).state = [
                          for (final t in types)
                            if (t != type) t,
                        ],
                  ),
          );
        },
      ),
    );
  }
}
