import 'package:flutter/foundation.dart';

/// A spending label the user logs against (Food, Transport, their own...).
@immutable
class LogCategory {
  const LogCategory(this.name, this.colorValue);

  factory LogCategory.fromJson(Map<String, dynamic> j) =>
      LogCategory(j['name'] as String, j['color'] as int);

  final String name;
  final int colorValue;

  Map<String, dynamic> toJson() => {'name': name, 'color': colorValue};

  static const defaults = [
    LogCategory('Food', 0xFFF2B33D),
    LogCategory('Transport', 0xFF4EA3F8),
    LogCategory('Shopping', 0xFFE879A9),
    LogCategory('Bills', 0xFF9A85F2),
    LogCategory('Health', 0xFF33B5A5),
    LogCategory('Fun', 0xFFF0717A),
    LogCategory('Other', 0xFFD9A47A),
  ];
}
