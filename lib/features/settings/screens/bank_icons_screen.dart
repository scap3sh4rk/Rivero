import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/photo_picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Settings > Bank icons: one picture per bank, used for every account,
/// card and payment of that bank. Rivero ships no bank logos (they are
/// trademarks): add a screenshot or photo of yours once, here.
class BankIconsScreen extends ConsumerWidget {
  const BankIconsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const BankIconsScreen()));

  Future<void> _pick(BuildContext context, WidgetRef ref, String bank) async {
    final picked = await pickPhoto(context);
    if (picked == null) return;
    final key = BankIcons.key(bank);
    final icons = ref.read(bankIconsProvider);
    final path = await MediaStore.keep(
      picked,
      folder: MediaStore.bankIcons,
      name: key,
    );
    await MediaStore.remove(icons[key]);
    ref.read(bankIconsProvider.notifier).state = {...icons, key: path};
  }

  Future<void> _remove(WidgetRef ref, String bank) async {
    final key = BankIcons.key(bank);
    final icons = ref.read(bankIconsProvider);
    await MediaStore.remove(icons[key]);
    ref.read(bankIconsProvider.notifier).state = {...icons}..remove(key);
  }

  Future<void> _addBank(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Which bank?'),
        content: TextField(
          key: const ValueKey('bank-name'),
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Kotak, IDFC First'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Pick a picture'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await _pick(context, ref, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(bankIconsProvider);
    // The banks of your accounts and cards, plus any you added a picture for.
    final banks = <String, String>{
      for (final a
          in ref.watch(activePhysicalAccountsProvider).value ??
              const <PhysicalAccount>[])
        if (a.institution.trim().isNotEmpty)
          BankIcons.key(a.institution): a.institution.trim(),
    };
    for (final k in icons.keys) {
      banks.putIfAbsent(k, k.toUpperCase);
    }
    final list = banks.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        showEye: false, // the hide-amounts eye is for money pages
        title: 'Bank icons',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: RiveroSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.xl),
            child: Text(
              'Add a picture once per bank (a screenshot of its logo works) '
              'and every account, card and payment of that bank uses it. '
              'A picture set on one account still wins for that account.',
              style: RiveroTypography.bodySmall,
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          for (final e in list)
            ListTile(
              key: ValueKey('bank-icon-${e.key}'),
              leading: BankBadge(name: e.value, size: 40),
              title: Text(e.value),
              subtitle: Text(
                icons.containsKey(e.key) ? 'Picture set' : 'Initials for now',
              ),
              onTap: () => _pick(context, ref, e.value),
              trailing: icons.containsKey(e.key)
                  ? IconButton(
                      tooltip: 'Use initials again',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _remove(ref, e.value),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('bank-add'),
                onPressed: () => _addBank(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Another bank'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
