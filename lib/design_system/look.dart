import 'dart:convert';

import 'package:flutter/material.dart';

/// How big a group of cards is drawn on the Accounts page.
enum CardSize { compact, standard, large }

/// Dark-mode backgrounds (light mode has its own pair).
enum DarkBackground { black, charcoal, midnight }

enum LightBackground { paper, white }

/// The accent used for buttons, selection and the active tab: a shade for
/// dark mode and a deeper one for light mode.
class AccentChoice {
  const AccentChoice(this.name, this.dark, this.light);
  final String name;
  final Color dark;
  final Color light;

  static const all = [
    AccentChoice('Sky', Color(0xFF4EA3F8), Color(0xFF1A73D9)),
    AccentChoice('Indigo', Color(0xFF7C8CFF), Color(0xFF4351D6)),
    AccentChoice('Violet', Color(0xFFA48BFA), Color(0xFF6D4CDB)),
    AccentChoice('Teal', Color(0xFF2CC5BC), Color(0xFF0E8C85)),
    AccentChoice('Green', Color(0xFF3DD07E), Color(0xFF178A49)),
    AccentChoice('Amber', Color(0xFFF5B841), Color(0xFFB37800)),
    AccentChoice('Orange', Color(0xFFFF8A3D), Color(0xFFC85A12)),
    AccentChoice('Coral', Color(0xFFF2555A), Color(0xFFC8303A)),
    AccentChoice('Mono', Color(0xFFE4E4E7), Color(0xFF27272A)),
    // Added later: new ones go at the end so saved choices keep their place.
    AccentChoice('Cyan', Color(0xFF38D3F5), Color(0xFF0B8BA8)),
    AccentChoice('Mint', Color(0xFF5EE0B0), Color(0xFF15936A)),
    AccentChoice('Lime', Color(0xFFB4E04A), Color(0xFF5E8A12)),
    AccentChoice('Gold', Color(0xFFE8C468), Color(0xFF9A7414)),
    AccentChoice('Rose', Color(0xFFFF7A9C), Color(0xFFC23A62)),
    AccentChoice('Pink', Color(0xFFF472B6), Color(0xFFBE2C82)),
    AccentChoice('Magenta', Color(0xFFD86AF0), Color(0xFF9A2DB4)),
    AccentChoice('Lavender', Color(0xFFC4B5FD), Color(0xFF6A54C9)),
    AccentChoice('Ocean', Color(0xFF3B82F6), Color(0xFF1D4ED8)),
    AccentChoice('Slate', Color(0xFF9AA8BD), Color(0xFF475569)),
  ];
}

/// Everything the user can change about how Rivero looks (Settings >
/// Appearance). Saved as JSON; unknown or missing values fall back to the
/// defaults, so older saves keep working.
@immutable
class Look {
  const Look({
    this.accent = 0,
    this.darkBackground = DarkBackground.black,
    this.lightBackground = LightBackground.paper,
    this.weight = 0,
    this.textScale = 1,
    this.corners = 12,
    this.bankCards = CardSize.standard,
    this.creditCards = CardSize.standard,
    this.heroScale = 1,
    this.borders = true,
  });

  factory Look.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const Look();
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.where((v) => v.name == name).firstOrNull ?? fallback;
      double dbl(Object? v, double fallback, double min, double max) =>
          v is num ? v.toDouble().clamp(min, max) : fallback;
      return Look(
        accent: (j['accent'] as int? ?? 0).clamp(
          0,
          AccentChoice.all.length - 1,
        ),
        darkBackground: pick(
          DarkBackground.values,
          j['darkBackground'],
          DarkBackground.black,
        ),
        lightBackground: pick(
          LightBackground.values,
          j['lightBackground'],
          LightBackground.paper,
        ),
        weight: (j['weight'] as int? ?? 0).clamp(-1, 2),
        textScale: dbl(j['textScale'], 1, minText, maxText),
        corners: dbl(j['corners'], 12, 0, 28),
        bankCards: pick(CardSize.values, j['bankCards'], CardSize.standard),
        creditCards: pick(CardSize.values, j['creditCards'], CardSize.standard),
        heroScale: dbl(j['heroScale'], 1, minHero, maxHero),
        borders: j['borders'] as bool? ?? true,
      );
    } on Object {
      return const Look();
    }
  }

  static const minText = 0.85;
  static const maxText = 1.3;
  static const minHero = 0.75;
  static const maxHero = 1.25;

  /// Index into [AccentChoice.all].
  final int accent;
  final DarkBackground darkBackground;
  final LightBackground lightBackground;

  /// Font weight shift in steps of 100 (-1 lighter … 2 heavier).
  final int weight;

  /// Text size multiplier on top of the phone's own setting.
  final double textScale;

  /// Card corner radius in logical pixels.
  final double corners;
  final CardSize bankCards;
  final CardSize creditCards;

  /// Size of the Safe to spend number on Home.
  final double heroScale;

  /// Thin outlines around cards.
  final bool borders;

  Look copyWith({
    int? accent,
    DarkBackground? darkBackground,
    LightBackground? lightBackground,
    int? weight,
    double? textScale,
    double? corners,
    CardSize? bankCards,
    CardSize? creditCards,
    double? heroScale,
    bool? borders,
  }) => Look(
    accent: accent ?? this.accent,
    darkBackground: darkBackground ?? this.darkBackground,
    lightBackground: lightBackground ?? this.lightBackground,
    weight: weight ?? this.weight,
    textScale: textScale ?? this.textScale,
    corners: corners ?? this.corners,
    bankCards: bankCards ?? this.bankCards,
    creditCards: creditCards ?? this.creditCards,
    heroScale: heroScale ?? this.heroScale,
    borders: borders ?? this.borders,
  );

  String toJson() => jsonEncode({
    'accent': accent,
    'darkBackground': darkBackground.name,
    'lightBackground': lightBackground.name,
    'weight': weight,
    'textScale': textScale,
    'corners': corners,
    'bankCards': bankCards.name,
    'creditCards': creditCards.name,
    'heroScale': heroScale,
    'borders': borders,
  });

  @override
  bool operator ==(Object other) => other is Look && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// The look in use, set by the app root before building (like
/// `RiveroColors.isLight`); tokens read it.
abstract final class RiveroLook {
  static Look current = const Look();
}
