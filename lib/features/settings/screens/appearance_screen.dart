import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/look.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Settings > Appearance: theme, background, accent, font, weight, text
/// size, card corners and outlines, card sizes on Accounts and the size of
/// the Safe to spend number. Every change applies at once, everywhere,
/// and is shown in the preview at the top.
class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()));

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  // Slider positions while dragging; the look changes when the drag ends,
  // so the whole app is not rebuilt (and saved) on every pixel.
  double? _text;
  double? _hero;
  double? _corners;

  void _set(Look Function(Look) change) {
    HapticFeedback.selectionClick();
    final n = ref.read(lookProvider.notifier);
    n.state = change(n.state);
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(lookProvider);
    final mode = ref.watch(themeModeProvider);
    final font = ref.watch(fontFamilyProvider);
    final light = RiveroColors.isLight;

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        showEye: false, // the hide-amounts eye is for money pages
        title: 'Appearance',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          const _Preview(),
          const _Section('Theme'),
          _Segments<AppThemeMode>(
            key: const ValueKey('look-theme'),
            value: mode,
            options: const {
              AppThemeMode.dark: 'Dark',
              AppThemeMode.light: 'Light',
              AppThemeMode.system: 'Phone',
            },
            onChanged: (v) => ref.read(themeModeProvider.notifier).state = v,
          ),
          const _Section('Background'),
          if (light)
            _Segments<LightBackground>(
              key: const ValueKey('look-light-bg'),
              value: look.lightBackground,
              options: const {
                LightBackground.paper: 'Warm paper',
                LightBackground.white: 'Clean white',
              },
              onChanged: (v) => _set((l) => l.copyWith(lightBackground: v)),
            )
          else
            _Segments<DarkBackground>(
              key: const ValueKey('look-dark-bg'),
              value: look.darkBackground,
              options: const {
                DarkBackground.black: 'Pure black',
                DarkBackground.charcoal: 'Charcoal',
                DarkBackground.midnight: 'Midnight',
              },
              onChanged: (v) => _set((l) => l.copyWith(darkBackground: v)),
            ),
          const _Section('Accent colour'),
          Wrap(
            spacing: RiveroSpacing.md,
            runSpacing: RiveroSpacing.md,
            children: [
              for (var i = 0; i < AccentChoice.all.length; i++)
                _Swatch(
                  key: ValueKey('accent-${AccentChoice.all[i].name}'),
                  choice: AccentChoice.all[i],
                  light: light,
                  selected: look.accent == i,
                  onTap: () => _set((l) => l.copyWith(accent: i)),
                ),
            ],
          ),
          const _Section('Font'),
          Wrap(
            spacing: RiveroSpacing.sm,
            runSpacing: RiveroSpacing.sm,
            children: [
              for (final f in RiveroFonts.families)
                ChoiceChip(
                  key: ValueKey('font-$f'),
                  label: Text(f, style: TextStyle(fontFamily: f)),
                  selected: font == f,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    ref.read(fontFamilyProvider.notifier).state = f;
                  },
                ),
            ],
          ),
          const _Section('Font weight'),
          _Segments<int>(
            key: const ValueKey('look-weight'),
            value: look.weight,
            options: const {-1: 'Light', 0: 'Regular', 1: 'Bold', 2: 'Heavy'},
            onChanged: (v) => _set((l) => l.copyWith(weight: v)),
          ),
          const _Section('Text size'),
          _SliderRow(
            key: const ValueKey('look-text'),
            value: _text ?? look.textScale,
            min: Look.minText,
            max: Look.maxText,
            divisions: 9,
            label: '${((_text ?? look.textScale) * 100).round()}%',
            onChanged: (v) => setState(() => _text = v),
            onChangeEnd: (v) {
              _text = null;
              _set((l) => l.copyWith(textScale: v));
            },
          ),
          const _Section('Safe to spend number'),
          _SliderRow(
            key: const ValueKey('look-hero'),
            value: _hero ?? look.heroScale,
            min: Look.minHero,
            max: Look.maxHero,
            divisions: 10,
            label: '${((_hero ?? look.heroScale) * 100).round()}%',
            onChanged: (v) => setState(() => _hero = v),
            onChangeEnd: (v) {
              _hero = null;
              _set((l) => l.copyWith(heroScale: v));
            },
          ),
          const _Section('Bank & cash cards'),
          _Segments<CardSize>(
            key: const ValueKey('look-bank-cards'),
            value: look.bankCards,
            options: _sizes,
            onChanged: (v) => _set((l) => l.copyWith(bankCards: v)),
          ),
          _Hint(switch (look.bankCards) {
            CardSize.compact => 'One line each: name and balance',
            CardSize.standard => 'Name and digits in full, balance alongside',
            CardSize.large =>
              'Large balance, when it was confirmed and which bills it pays',
          }),
          const _Section('Credit cards'),
          _Segments<CardSize>(
            key: const ValueKey('look-credit-cards'),
            value: look.creditCards,
            options: _sizes,
            onChanged: (v) => _set((l) => l.copyWith(creditCards: v)),
          ),
          _Hint(switch (look.creditCards) {
            CardSize.compact => 'Outstanding, usage and whether you can pay',
            CardSize.standard => 'Adds the billing cycle, due date and limit',
            CardSize.large => 'Everything, with a larger outstanding amount',
          }),
          const _Section('Card corners'),
          _SliderRow(
            key: const ValueKey('look-corners'),
            value: _corners ?? look.corners,
            min: 0,
            max: 28,
            divisions: 7,
            label: '${(_corners ?? look.corners).round()}',
            onChanged: (v) => setState(() => _corners = v),
            onChangeEnd: (v) {
              _corners = null;
              _set((l) => l.copyWith(corners: v));
            },
          ),
          SwitchListTile(
            key: const ValueKey('look-borders'),
            contentPadding: EdgeInsets.zero,
            title: Text('Card outlines', style: RiveroTypography.bodyLarge),
            subtitle: Text(
              'A thin line around each card',
              style: RiveroTypography.bodySmall,
            ),
            value: look.borders,
            onChanged: (v) => _set((l) => l.copyWith(borders: v)),
          ),
          const SizedBox(height: RiveroSpacing.lg),
          OutlinedButton(
            key: const ValueKey('look-reset'),
            onPressed:
                look == const Look() && font == RiveroFonts.families.first
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    ref.read(lookProvider.notifier).state = const Look();
                    ref.read(fontFamilyProvider.notifier).state =
                        RiveroFonts.families.first;
                  },
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Back to the original look'),
          ),
        ],
      ),
    );
  }

  static const Map<CardSize, String> _sizes = {
    CardSize.compact: 'Compact',
    CardSize.standard: 'Standard',
    CardSize.large: 'Large',
  };
}

/// A small sample of the app in the current look.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return RiveroCard(
      key: const ValueKey('look-preview'),
      isElevated: true,
      padding: const EdgeInsets.all(RiveroSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAFE TO SPEND PER DAY',
            style: RiveroTypography.labelSmall.copyWith(
              letterSpacing: 1.6,
              color: RiveroColors.textMuted,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹1,250',
              style: RiveroTypography.financialHero.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '₹18,750 safe · 15 days to payday',
            style: RiveroTypography.bodyMedium,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Row(
              children: [
                const BankBadge(name: 'HDFC Bank', size: 36, circle: true),
                const SizedBox(width: RiveroSpacing.md),
                Expanded(
                  child: Text(
                    'Salary account',
                    style: RiveroTypography.titleMedium,
                  ),
                ),
                Text('₹48,250', style: RiveroTypography.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          Row(
            children: [
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Add'),
              ),
              const SizedBox(width: RiveroSpacing.sm),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Ignore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: RiveroSpacing.xl,
      bottom: RiveroSpacing.sm,
    ),
    child: Text(title, style: RiveroTypography.titleMedium),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RiveroSpacing.xs),
    child: Text(text, style: RiveroTypography.bodySmall),
  );
}

/// One of a few options, as a segmented row that never cuts its labels.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final e in options.entries)
          ButtonSegment(
            value: e.key,
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          label,
          textAlign: TextAlign.end,
          style: RiveroTypography.labelLarge,
        ),
      ),
    ],
  );
}

/// A round accent sample; the picked one has a ring.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.light,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AccentChoice choice;
  final bool light;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = light ? choice.light : choice.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: '${choice.name} accent',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color:
                            ThemeData.estimateBrightnessForColor(c) ==
                                Brightness.light
                            ? const Color(0xFF04101F)
                            : Colors.white,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(choice.name, style: RiveroTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}
