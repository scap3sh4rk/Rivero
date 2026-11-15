import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Pictures the user added per bank (Settings > Bank icons), used for every
/// account, card and payment of that bank. Rivero ships no bank logos
/// (they are trademarks); the user adds their own.
abstract final class BankIcons {
  /// "HDFC Bank" -> "hdfcbank": the same bank however it is written.
  static String key(String name) =>
      name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// The picture for [name]: the same bank, or one whose name starts the
  /// other ("SBI" for "SBI Card", "HDFC Bank" for "HDFC Bank Millennia").
  static String? lookup(Map<String, String> icons, String name) {
    if (icons.isEmpty) return null;
    final k = key(name);
    final exact = icons[k];
    if (exact != null || k.length < 3) return exact;
    String? best;
    var bestLength = 0;
    for (final e in icons.entries) {
      final match =
          e.key.length >= 3 && (k.startsWith(e.key) || e.key.startsWith(k));
      // The longest match is the most specific bank.
      if (match && e.key.length > bestLength) {
        best = e.value;
        bestLength = e.key.length;
      }
    }
    return best;
  }
}

/// Coloured monogram for an institution, or a picture: the one chosen for
/// this account, else the user's picture for the bank.
/// The tint is derived from the name so it is stable across launches.
class BankBadge extends ConsumerWidget {
  const BankBadge({
    required this.name,
    super.key,
    this.size = 44,
    this.circle = false,
    this.color,
    this.imagePath,
    this.bankIcon = true,
  });

  /// Use the bank's picture when there is no own one (off for people).
  final bool bankIcon;

  /// Explicit tint (account / category colour); else derived from [name].
  final Color? color;

  /// A user-chosen picture shown instead of initials, if the file exists.
  final String? imagePath;

  final String name;
  final double size;

  /// Round (Slice activity rows) instead of a rounded square.
  final bool circle;

  static const List<Color> _tints = [
    RiveroColors.salaryAccent,
    RiveroColors.expenseAccent,
    RiveroColors.investmentAccent,
    RiveroColors.savingsAccent,
    RiveroColors.customAccent,
    RiveroColors.liabilityAccent,
    RiveroColors.walletAccent,
  ];

  /// Stable tint for a name (used when no colour was chosen).
  static Color tintFor(String name) =>
      _tints[name.codeUnits.fold(0, (a, b) => a + b) % _tints.length];

  /// First one or two initials, e.g. "HDFC Bank" -> "HB", "SBI" -> "S".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = color ?? tintFor(name);
    final own = imagePath;
    final path = own != null && File(own).existsSync()
        ? own
        : bankIcon
        ? BankIcons.lookup(ref.watch(bankIconsProvider), name)
        : null;
    if (path != null && File(path).existsSync()) {
      final radius = circle ? size / 2 : size * 0.3;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initials(name),
        style: RiveroTypography.titleMedium.copyWith(
          color: tint,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
