import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/goals/goals_screen.dart';

/// Home: the goals closest to their date, each with a bar and whether it is
/// on track. Nothing when there are no goals.
class GoalsHomeCard extends ConsumerWidget {
  const GoalsHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = [...?ref.watch(goalsProvider).value]
      ..sort((a, b) => a.goal.by.compareTo(b.goal.by));
    if (list.isEmpty) return const SizedBox.shrink();
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) =>
        privacy ? '••••' : CurrencyFormatter.formatCompact(v);
    return Padding(
      padding: const EdgeInsets.only(top: RiveroSpacing.md),
      child: RiveroCard(
        key: const ValueKey('home-goals'),
        onTap: () => GoalsScreen.open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'GOALS',
                    style: RiveroTypography.labelSmall.copyWith(
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (list.length > 2)
                  Text(
                    '+${list.length - 2} more',
                    style: RiveroTypography.bodySmall,
                  ),
              ],
            ),
            for (final p in list.take(2)) ...[
              const SizedBox(height: RiveroSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RiveroTypography.titleMedium,
                    ),
                  ),
                  Text(
                    '${money(p.savedMinorUnits)} / '
                    '${money(p.goal.targetMinorUnits)}',
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: RiveroSpacing.xs),
              ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  // Display only; the amounts stay integers.
                  value: p.goal.targetMinorUnits == 0
                      ? 1
                      : (p.savedMinorUnits / p.goal.targetMinorUnits).clamp(
                          0.0,
                          1.0,
                        ),
                  minHeight: 6,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  color: p.reached ? RiveroColors.success : RiveroColors.accent,
                ),
              ),
              const SizedBox(height: RiveroSpacing.xs),
              Text(
                goalStatus(p, money),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RiveroTypography.bodySmall.copyWith(
                  color: goalStatusColor(p),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
