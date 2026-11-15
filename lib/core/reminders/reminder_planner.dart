import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/utils/currency_formatter.dart';

/// One reminder for the phone to show at [at].
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable per reminder (re-planning replaces it, never duplicates it).
  final String id;
  final DateTime at;
  final String title;
  final String body;

  Map<String, Object> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
  };
}

/// Which reminders the user wants (Settings > Reminders).
class ReminderPrefs {
  const ReminderPrefs({
    this.cardBills = true,
    this.autopay = true,
    this.owed = true,
  });

  final bool cardBills;
  final bool autopay;

  /// Money owed to you for a month, and debts you promised to repay.
  final bool owed;
}

/// Works out the reminders for the next two weeks from the user's data:
/// card bills (3 days and 1 day before the due date, with whether the bank
/// balance covers them), autopay the day before, debts due the day before,
/// and money owed to you for more than 30 days. All at 9 am, local time.
abstract final class ReminderPlanner {
  static const horizon = Duration(days: 14);

  static DateTime _at9(DateTime day) =>
      DateTime(day.year, day.month, day.day, 9);

  static List<Reminder> plan({
    required DateTime now,
    required List<PhysicalAccount> accounts,
    required List<Mandate> mandates,
    required List<Due> dues,
    ReminderPrefs prefs = const ReminderPrefs(),
  }) {
    final out = <Reminder>[];
    final until = now.add(horizon);
    final f = DateFormat('d MMM');
    String money(int v) => CurrencyFormatter.format(v);
    bool upcoming(DateTime t) => t.isAfter(now) && t.isBefore(until);
    final bills = CardBills.of(accounts);

    if (prefs.cardBills) {
      for (final c in accounts.where((a) => a.isLiability && a.isActive)) {
        final owed = c.balanceMinorUnits < 0 ? -c.balanceMinorUnits : 0;
        final cycle = CardCycle.of(
          statementDay: c.statementDay,
          paymentDueDay: c.paymentDueDay,
          now: now,
        );
        if (owed == 0 || cycle == null) continue;
        final afford = bills.byCard[c.id];
        if (afford == null) continue; // a loan: its instalments are autopays
        final from = bills.payerOf[c.id]?.name;
        final tail = afford.canPay
            ? (from == null
                  ? 'Your accounts can cover it.'
                  : '$from can cover it.')
            : 'Short by ${money(afford.shortBy)}'
                  '${from == null ? '' : ' in $from'}.';
        for (final daysBefore in const [3, 1]) {
          final at = _at9(cycle.dueDate.subtract(Duration(days: daysBefore)));
          if (!upcoming(at)) continue;
          out.add(
            Reminder(
              id: 'card-${c.id}-${f.format(cycle.dueDate)}-$daysBefore',
              at: at,
              title:
                  '${c.name} bill ${money(owed)} due '
                  '${daysBefore == 1 ? 'tomorrow' : 'in $daysBefore days'}',
              body: 'Pay by ${f.format(cycle.dueDate)}. $tail',
            ),
          );
        }
      }
    }

    if (prefs.autopay) {
      final byId = {for (final a in accounts) a.id: a};
      for (final m in mandates.where((m) => m.status == MandateStatus.active)) {
        final due = m.nextExecutionDate;
        if (due == null) continue;
        final at = _at9(due.subtract(const Duration(days: 1)));
        if (!upcoming(at)) continue;
        final amount = m.isVariableAmount
            ? (m.maxCapMinorUnits ?? m.amountMinorUnits)
            : m.amountMinorUnits;
        final acc = byId[m.physicalAccountId];
        final short =
            acc != null && !acc.isLiability && acc.balanceMinorUnits < amount;
        out.add(
          Reminder(
            id: 'autopay-${m.id}-${f.format(due)}',
            at: at,
            title: '${m.payee} autopay tomorrow',
            body: short
                ? '${money(amount)} from ${acc.name}, which holds '
                      '${money(acc.balanceMinorUnits)}: short by '
                      '${money(amount - acc.balanceMinorUnits)}.'
                : '${money(amount)}${acc == null ? '' : ' from ${acc.name}'}.',
          ),
        );
      }
    }

    if (prefs.owed) {
      for (final d in dues.where((d) => d.status == DueStatus.open)) {
        final left = d.amountMinorUnits - d.receivedMinorUnits;
        if (left <= 0) continue;
        if (d.kind == DueKind.borrowed) {
          final due = d.dueDate;
          if (due == null) continue;
          final at = _at9(due.subtract(const Duration(days: 1)));
          if (!upcoming(at)) continue;
          out.add(
            Reminder(
              id: 'debt-${d.id}',
              at: at,
              title: 'Pay back ${d.person} tomorrow',
              body: 'You owe ${money(left)}, due ${f.format(due)}.',
            ),
          );
        } else {
          // Owed to you for over 30 days: one nudge, on the 30th day.
          final at = _at9(d.createdAt.add(const Duration(days: 30)));
          if (!upcoming(at)) continue;
          out.add(
            Reminder(
              id: 'owed-${d.id}',
              at: at,
              title: '${d.person} still owes you ${money(left)}',
              body:
                  'Since ${f.format(d.createdAt)}. Tap to settle it in Rivero.',
            ),
          );
        }
      }
    }

    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }
}

/// Re-plans every reminder from the database and hands them to the phone.
/// Called on start, on resume, at midnight and when a reminder setting
/// changes. [schedule] receives the JSON plan (the Android bridge).
Future<List<Reminder>> replanReminders(
  RiveroDatabase db,
  Future<void> Function(String json) schedule, {
  DateTime? now,
}) async {
  Future<bool> on(String key) async => await db.settingsDao.get(key) != '0';
  final prefs = ReminderPrefs(
    cardBills: await on(SettingKeys.remindCards),
    autopay: await on(SettingKeys.remindAutopay),
    owed: await on(SettingKeys.remindOwed),
  );
  final plan = ReminderPlanner.plan(
    now: now ?? DateTime.now(),
    // In rupees, like the rest of the app's totals.
    accounts: ExchangeRates.fromJson(
      await db.settingsDao.get(SettingKeys.exchangeRates),
    ).inHome(await db.accountsDao.getAllActivePhysicalAccounts()),
    mandates: await db.mandatesDao.getAllMandates(),
    dues: await db.select(db.dues).get(),
    prefs: prefs,
  );
  await schedule(jsonEncode([for (final r in plan) r.toJson()]));
  return plan;
}
