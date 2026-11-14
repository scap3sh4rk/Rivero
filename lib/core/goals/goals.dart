import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// "Trip ₹50,000 by June." A goal never holds money: its progress is read
/// from a linked account's balance, or from what was paid into a plan
/// category since the goal began.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetMinorUnits,
    required this.by,
    required this.start,
    this.accountId,
    this.bucketId,
  });

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String,
    name: j['name'] as String,
    targetMinorUnits: j['target'] as int,
    by: DateTime.parse(j['by'] as String),
    start: DateTime.parse(j['start'] as String),
    accountId: j['account'] as String?,
    bucketId: j['bucket'] as String?,
  );

  final String id;
  final String name;
  final int targetMinorUnits;
  final DateTime by;
  final DateTime start;
  final String? accountId;
  final String? bucketId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': targetMinorUnits,
    'by': by.toIso8601String(),
    'start': start.toIso8601String(),
    'account': ?accountId,
    'bucket': ?bucketId,
  };
}

class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.savedMinorUnits,
    required this.perMonthMinorUnits,
    required this.behindByMinorUnits,
  });

  final Goal goal;
  final int savedMinorUnits;

  /// Still needed each month (rounded up to the rupee) to reach it on time.
  final int perMonthMinorUnits;

  /// How far below a straight line from start to target date (0 = on track).
  final int behindByMinorUnits;

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

  Future<GoalProgress> progress(Goal g, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    var saved = 0;
    if (g.accountId != null) {
      final a = await db.accountsDao.getPhysicalAccountById(g.accountId!);
      saved = a == null || a.isLiability ? 0 : a.balanceMinorUnits;
    } else if (g.bucketId != null) {
      // Money out of the salary account into this category (the "in" leg of
      // a transfer carries the same category; only count the "out" leg).
      final paid =
          await (db.select(db.transactions)..where(
                (t) =>
                    t.allocationBucketId.equals(g.bucketId!) &
                    t.amountMinorUnits.isSmallerThanValue(0) &
                    t.transactionState.isIn([
                      TransactionState.confirmed.name,
                      TransactionState.reconciled.name,
                    ]) &
                    t.transactionTimestamp.isBiggerOrEqualValue(g.start),
              ))
              .get();
      saved = paid.fold(0, (s, t) => s - t.amountMinorUnits);
    }
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
    );
  }
}
