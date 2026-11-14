import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';

/// "When the payee or message contains X (and the amount is in a range),
/// put it in category Y, or ignore it." Rules run on every capture before it
/// reaches review; the user still Accepts it unless automatic accept is on.
class CaptureRule {
  const CaptureRule({
    required this.contains,
    this.category,
    this.ignore = false,
    this.minMinorUnits,
    this.maxMinorUnits,
  });

  factory CaptureRule.fromJson(Map<String, dynamic> j) => CaptureRule(
    contains: j['contains'] as String,
    category: j['category'] as String?,
    ignore: j['ignore'] == true,
    minMinorUnits: j['min'] as int?,
    maxMinorUnits: j['max'] as int?,
  );

  final String contains;
  final String? category;
  final bool ignore;

  /// Optional amount range, in paise, on the payment's size (sign ignored).
  final int? minMinorUnits;
  final int? maxMinorUnits;

  Map<String, dynamic> toJson() => {
    'contains': contains,
    'category': ?category,
    if (ignore) 'ignore': true,
    'min': ?minMinorUnits,
    'max': ?maxMinorUnits,
  };

  bool matches(String text, int amountMinorUnits) {
    final size = amountMinorUnits.abs();
    return contains.trim().isNotEmpty &&
        text.toLowerCase().contains(contains.trim().toLowerCase()) &&
        (minMinorUnits == null || size >= minMinorUnits!) &&
        (maxMinorUnits == null || size <= maxMinorUnits!);
  }
}

class CaptureRules {
  const CaptureRules(this.db);

  final RiveroDatabase db;

  Future<List<CaptureRule>> load() async {
    final raw = await db.settingsDao.get(SettingKeys.captureRules);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          CaptureRule.fromJson(j as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<CaptureRule> rules) => db.settingsDao.set(
    SettingKeys.captureRules,
    jsonEncode([for (final r in rules) r.toJson()]),
  );

  Future<void> add(CaptureRule rule) async {
    await save([...await load(), rule]);
  }

  /// The first rule (in the user's order) matching the payee or message.
  Future<CaptureRule?> match({
    required String merchant,
    required String message,
    required int amountMinorUnits,
  }) async {
    for (final r in await load()) {
      if (r.matches('$merchant\n$message', amountMinorUnits)) return r;
    }
    return null;
  }

  /// After the user files a capture from [merchant] under [category]: true
  /// when they have now done so at least twice and no rule covers it yet,
  /// so the app can offer "always put [merchant] in [category]".
  Future<bool> shouldSuggest(String merchant, String category) async {
    final m = merchant.trim();
    if (m.isEmpty || m == 'Unknown Merchant') return false;
    final rules = await load();
    final lower = m.toLowerCase();
    if (rules.any((r) => lower.contains(r.contains.trim().toLowerCase()))) {
      return false;
    }
    final same =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.ingestionLogId.isNotNull() &
                  t.merchant.equals(merchant) &
                  t.category.equals(category),
            ))
            .get();
    return same.length >= 2;
  }
}
