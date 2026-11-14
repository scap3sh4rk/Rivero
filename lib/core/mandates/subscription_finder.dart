import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:uuid/uuid.dart';

/// A payment that looks like a subscription nobody registered as autopay.
class RecurringSuggestion {
  const RecurringSuggestion({
    required this.merchant,
    required this.amountMinorUnits,
    required this.frequency,
    required this.accountId,
    required this.next,
    required this.count,
  });

  final String merchant;
  final int amountMinorUnits;
  final MandateFrequency frequency;
  final String accountId;
  final DateTime next;

  /// How many payments the pattern is based on.
  final int count;
}

/// Looks through the last six months for the same payee paid a similar
/// amount (within 10%) at a regular interval (weekly or monthly), at least
/// three times, and not already an autopay.
class SubscriptionFinder {
  const SubscriptionFinder(this.db);

  final RiveroDatabase db;

  static const List<TransactionType> _spend = [
    TransactionType.expense,
    TransactionType.creditCardPurchase,
  ];

  Future<List<RecurringSuggestion>> find({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final txns =
        await (db.select(db.transactions)
              ..where(
                (t) =>
                    t.amountMinorUnits.isSmallerThanValue(0) &
                    t.transactionType.isIn(_spend.map((e) => e.name)) &
                    t.transactionState.isIn([
                      TransactionState.confirmed.name,
                      TransactionState.reconciled.name,
                    ]) &
                    t.transactionTimestamp.isBiggerOrEqualValue(
                      today.subtract(const Duration(days: 183)),
                    ),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.transactionTimestamp)]))
            .get();
    final payees = [
      for (final m in await db.select(db.mandates).get())
        m.payee.trim().toLowerCase(),
      ...await _dismissed(),
    ];

    final groups = <String, List<LedgerTransaction>>{};
    for (final t in txns) {
      final key = t.merchant.trim().toLowerCase();
      if (key.isEmpty || key == 'unknown merchant') continue;
      (groups[key] ??= []).add(t);
    }

    final out = <RecurringSuggestion>[];
    for (final MapEntry(:key, value: g) in groups.entries) {
      if (g.length < 3) continue;
      if (payees.any((p) => p.contains(key) || key.contains(p))) continue;
      final last = g.last;
      final amount = -last.amountMinorUnits;
      // Similar amounts: each within 10% of the latest.
      if (g.any((t) => ((-t.amountMinorUnits) - amount).abs() * 10 > amount)) {
        continue;
      }
      final gaps = [
        for (var i = 1; i < g.length; i++)
          g[i].transactionTimestamp
              .difference(g[i - 1].transactionTimestamp)
              .inDays,
      ];
      final MandateFrequency freq;
      if (gaps.every((d) => d >= 26 && d <= 35)) {
        freq = MandateFrequency.monthly;
      } else if (gaps.every((d) => d >= 6 && d <= 8)) {
        freq = MandateFrequency.weekly;
      } else {
        continue;
      }
      var next = last.transactionTimestamp;
      while (!next.isAfter(today)) {
        next = freq == MandateFrequency.weekly
            ? next.add(const Duration(days: 7))
            : DateTime(next.year, next.month + 1, next.day);
      }
      out.add(
        RecurringSuggestion(
          merchant: last.merchant,
          amountMinorUnits: amount,
          frequency: freq,
          accountId: last.physicalAccountId,
          next: DateTime(next.year, next.month, next.day),
          count: g.length,
        ),
      );
    }
    return out;
  }

  /// Registers [s] as an autopay, so Safe to spend reserves it.
  Future<void> accept(RecurringSuggestion s) async {
    final now = DateTime.now();
    await db.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: Value(const Uuid().v4()),
        payee: Value(s.merchant),
        amountMinorUnits: Value(s.amountMinorUnits),
        frequency: Value(s.frequency),
        physicalAccountId: Value(s.accountId),
        startDate: Value(now),
        nextExecutionDate: Value(s.next),
        status: const Value(MandateStatus.active),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// "Not an autopay": never suggest this payee again.
  Future<void> dismiss(RecurringSuggestion s) async {
    final list = [...await _dismissed(), s.merchant.trim().toLowerCase()];
    await db.settingsDao.set(
      SettingKeys.dismissedSubscriptions,
      jsonEncode(list),
    );
  }

  Future<List<String>> _dismissed() async {
    final raw = await db.settingsDao.get(SettingKeys.dismissedSubscriptions);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<String>();
  }
}
