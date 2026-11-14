import 'package:flutter/foundation.dart';

/// A spending label the user logs against (Food, Transport, their own...).
@immutable
class LogCategory {
  const LogCategory(this.name, this.colorValue);

  factory LogCategory.fromJson(Map<String, dynamic> j) {
    final c = j['color'] as int;
    // Pink was retired from the palette; earlier choices move to coral.
    return LogCategory(j['name'] as String, _retired[c] ?? c);
  }

  static const _retired = {0xFFE879A9: 0xFFF2555A, 0xFFF0717A: 0xFFF2555A};

  final String name;
  final int colorValue;

  Map<String, dynamic> toJson() => {'name': name, 'color': colorValue};

  static const defaults = [
    LogCategory('Food', 0xFFFF8A3D),
    LogCategory('Transport', 0xFF4EA3F8),
    LogCategory('Shopping', 0xFFF2555A),
    LogCategory('Bills', 0xFF8B6CF6),
    LogCategory('Health', 0xFF2DBE6C),
    LogCategory('Fun', 0xFFF5B841),
    LogCategory('Other', 0xFF22B8B0),
  ];
}
