import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_group.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// What counts towards a goal.
enum GoalSourceKind {
  /// An account's value: a savings account, an FD (with the interest earned
  /// so far), a demat account.
  account,

  /// What was paid into a plan category since the goal began.
  bucket,

  /// Something the user values themselves: cash at home, stocks, gold.
  asset,
}

class GoalSource {
  const GoalSource.account(String this.id)
    : kind = GoalSourceKind.account,
      label = null,
      valueMinorUnits = 0;

  const GoalSource.bucket(String this.id)
    : kind = GoalSourceKind.bucket,
      label = null,
      valueMinorUnits = 0;

  const GoalSource.asset(String this.label, this.valueMinorUnits)
    : kind = GoalSourceKind.asset,
      id = null;

  factory GoalSource.fromJson(Map<String, dynamic> j) => switch (j['kind']) {
    'account' => GoalSource.account(j['id'] as String),
    'bucket' => GoalSource.bucket(j['id'] as String),
    _ => GoalSource.asset(
      j['label'] as String? ?? 'Other',
      j['value'] as int? ?? 0,
    ),
  };

  final GoalSourceKind kind;

  /// Account or plan-category id.
  final String? id;

  /// Assets: the user's name for it and what it is worth now (paise).
  final String? label;
  final int valueMinorUnits;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': ?id,
    'label': ?label,
    if (kind == GoalSourceKind.asset) 'value': valueMinorUnits,
  };
}

/// "Trip ₹50,000 by June." A goal never holds or moves money: its progress
/// is read from what counts towards it (accounts, FDs, plan categories, and
/// assets the user values).
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetMinorUnits,
    required this.by,
    required this.start,
    this.sources = const [],
  });

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String,
    name: j['name'] as String,
    targetMinorUnits: j['target'] as int,
    by: DateTime.parse(j['by'] as String),
    start: DateTime.parse(j['start'] as String),
    sources: [
      for (final s in (j['sources'] as List? ?? const []))
        GoalSource.fromJson(s as Map<String, dynamic>),
      // Goals saved before sources existed.
      if (j['account'] case final String id) GoalSource.account(id),
      if (j['bucket'] case final String id) GoalSource.bucket(id),
    ],
  );

  final String id;
  final String name;
  final int targetMinorUnits;
  final DateTime by;
  final DateTime start;
  final List<GoalSource> sources;

  Goal copyWith({
    String? name,
    int? targetMinorUnits,
    DateTime? by,
    List<GoalSource>? sources,
  }) => Goal(
    id: id,
    name: name ?? this.name,
    targetMinorUnits: targetMinorUnits ?? this.targetMinorUnits,
    by: by ?? this.by,
    start: start,
    sources: sources ?? this.sources,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': targetMinorUnits,
    'by': by.toIso8601String(),
    'start': start.toIso8601String(),
    'sources': [for (final s in sources) s.toJson()],
  };
}

class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.savedMinorUnits,
    required this.perMonthMinorUnits,
    required this.behindByMinorUnits,
    this.parts = const [],
  });

  final Goal goal;
  final int savedMinorUnits;

  /// Still needed each month (rounded up to the rupee) to reach it on time.
  final int perMonthMinorUnits;

  /// How far below a straight line from start to target date (0 = on track).
  final int behindByMinorUnits;

  /// Each source's name and what it adds (paise), in the goal's order.
  final List<({String name, int value})> parts;

  bool get reached => savedMinorUnits >= goal.targetMinorUnits;
}

class Goals {
  const Goals(this.db);

  final RiveroDatabase db;

  Future<List<Goal>> load() async {
    final raw = await db.settingsDao.get(SettingKeys.goals);
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final j in jsonDecode(raw) as List)
        Goal.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Goal> goals) => db.settingsDao.set(
    SettingKeys.goals,
    jsonEncode([for (final g in goals) g.toJson()]),
  );

  /// Adds [g], or replaces the goal with its id.
  Future<void> put(Goal g) async {
    final all = await load();
    final i = all.indexWhere((x) => x.id == g.id);
    await save(i < 0 ? [...all, g] : ([...all]..[i] = g));
  }

  Future<void> remove(String id) async {
    final rest = [
      for (final g in await load())
        if (g.id != id) g,
    ];
    await save(rest);
  }

  Future<GoalProgress> progress(Goal g, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rates = ExchangeRates.fromJson(
      await db.settingsDao.get(SettingKeys.exchangeRates),
    );
    final parts = <({String name, int value})>[];
    for (final s in g.sources) {
      switch (s.kind) {
        case GoalSourceKind.account:
          final a = await db.accountsDao.getPhysicalAccountById(s.id!);
          if (a == null || !a.isActive || a.isLiability) continue;
          final own = AccountGroup.isFixedDeposit(a)
              ? FixedDeposit.valueToday(a, today)
              : a.balanceMinorUnits;
          parts.add((
            name: a.name,
            value: rates.toHome(own < 0 ? 0 : own, a.currencyCode),
          ));
        case GoalSourceKind.bucket:
          final b = await (db.select(
            db.allocationBuckets,
          )..where((x) => x.id.equals(s.id!))).getSingleOrNull();
          // Money out of the salary account into this category (the "in"
          // leg of a transfer carries the same category; count "out" only).
          final paid =
              await (db.select(db.transactions)..where(
                    (t) =>
                        t.allocationBucketId.equals(s.id!) &
                        t.amountMinorUnits.isSmallerThanValue(0) &
                        t.transactionState.isIn([
                          TransactionState.confirmed.name,
                          TransactionState.reconciled.name,
                        ]) &
                        t.transactionTimestamp.isBiggerOrEqualValue(g.start),
                  ))
                  .get();
          parts.add((
            name: b?.name ?? 'Plan category',
            value: paid.fold(0, (sum, t) => sum - t.amountMinorUnits),
          ));
        case GoalSourceKind.asset:
          parts.add((name: s.label!, value: s.valueMinorUnits));
      }
    }
    final saved = parts.fold(0, (sum, p) => sum + p.value);
    final left = (g.targetMinorUnits - saved).clamp(0, g.targetMinorUnits);
    final months = ((g.by.year - today.year) * 12 + g.by.month - today.month)
        .clamp(1, 1200);
    // Round up to a whole rupee so "per month" never falls short.
    final perMonth = ((left + months - 1) ~/ months + 99) ~/ 100 * 100;
    final total = g.by.difference(g.start).inDays;
    final elapsed = today.difference(g.start).inDays.clamp(0, total);
    final expected = total <= 0
        ? g.targetMinorUnits
        : g.targetMinorUnits * elapsed ~/ total;
    return GoalProgress(
      goal: g,
      savedMinorUnits: saved,
      perMonthMinorUnits: left == 0 ? 0 : perMonth,
      behindByMinorUnits: (expected - saved).clamp(0, g.targetMinorUnits),
      parts: parts,
    );
  }
}
