import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/goals/goals_screen.dart';
import 'package:rivero/features/home/home_widgets.dart';

/// Settings > Home screen: which cards sit under Safe to spend, and in what
/// order. Safe to spend and the prompts that need you (review, backup...)
/// always show.
class HomeWidgetsScreen extends ConsumerWidget {
  const HomeWidgetsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const HomeWidgetsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = HomeWidget.chosen(ref.watch(homeWidgetsProvider));
    // Goals can only go on Home once there is a goal to show.
    final hasGoals = (ref.watch(goalsProvider).value ?? const []).isNotEmpty;
    // Chosen ones first in their order, then the rest.
    final all = [
      ...chosen,
      for (final w in HomeWidget.values)
        if (!chosen.contains(w)) w,
    ];
    void set(List<HomeWidget> next) =>
        ref.read(homeWidgetsProvider.notifier).state = [
          for (final w in next) w.name,
        ];

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        showEye: false, // the hide-amounts eye is for money pages
        title: 'Home screen',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: RiveroSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.xl),
            child: Text(
              'Pick the cards under Safe to spend and drag them into order. '
              'Safe to spend, and anything that needs you, always shows.',
              style: RiveroTypography.bodySmall,
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (from, to) {
              final list = [...all];
              final w = list.removeAt(from);
              list.insert(to > from ? to - 1 : to, w);
              set([
                for (final x in list)
                  if (chosen.contains(x)) x,
              ]);
            },
            children: [
              for (final w in all)
                SwitchListTile(
                  key: ValueKey('home-widget-${w.name}'),
                  title: Text(w.label),
                  subtitle: Text(
                    w == HomeWidget.goals && !hasGoals
                        ? 'Set a goal first: Plan > Goals'
                        : w.description,
                  ),
                  secondary: const Icon(Icons.drag_handle_rounded),
                  value:
                      chosen.contains(w) && (w != HomeWidget.goals || hasGoals),
                  onChanged: w == HomeWidget.goals && !hasGoals
                      ? null
                      : (on) => set(
                          on
                              ? [...chosen, w]
                              : [
                                  for (final x in chosen)
                                    if (x != w) x,
                                ],
                        ),
                ),
            ],
          ),
          Center(
            child: TextButton(
              onPressed: () => set(HomeWidget.defaults),
              child: const Text('Back to the default cards'),
            ),
          ),
        ],
      ),
    );
  }
}
