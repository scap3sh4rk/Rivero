import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/reminders/reminder_planner.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final now = DateTime(2026, 11, 14, 20); // Sat evening

  setUp(() async {
    db = RiveroDatabase.memory();
    Future<void> acc(String id, int bal, {bool card = false}) =>
        db.accountsDao.upsertPhysicalAccount(
          PhysicalAccountsCompanion(
            id: Value(id),
            name: Value(id),
            institution: const Value('Bank'),
            accountMask: const Value('1234'),
            balanceMinorUnits: Value(bal),
            isLiability: Value(card),
            creditLimitMinorUnits: Value(card ? 10000000 : 0),
            // Statement on the 1st, due on the 18th: due 18 Nov.
            statementDay: Value(card ? 1 : null),
            paymentDueDay: Value(card ? 18 : null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await acc('bank', 300000);
    await acc('card', -500000, card: true);
    await db.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: const Value('m'),
        payee: const Value('Netflix'),
        amountMinorUnits: const Value(64900),
        frequency: const Value(MandateFrequency.monthly),
        physicalAccountId: const Value('bank'),
        startDate: Value(now),
        nextExecutionDate: Value(DateTime(2026, 11, 20)),
        status: const Value(MandateStatus.active),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await DuesService(db).borrow(
      person: 'Meera',
      amountMinorUnits: 100000,
      dueDate: DateTime(2026, 11, 17),
    );
  });
  tearDown(() => db.close());

  test(
    'card bill, autopay and debt reminders for the next two weeks',
    () async {
      String? sent;
      final plan = await replanReminders(
        db,
        (json) async => sent = json,
        now: now,
      );
      final titles = plan.map((r) => r.title).toList();
      // Card: due 18 Nov; 3 days before (15th) and 1 day before (17th).
      expect(titles, contains('card bill ₹5,000.00 due in 3 days'));
      expect(titles, contains('card bill ₹5,000.00 due tomorrow'));
      final card = plan.firstWhere((r) => r.title.contains('in 3 days'));
      expect(card.at, DateTime(2026, 11, 15, 9));
      // ₹3,000 in the bank cannot cover ₹5,000.
      expect(card.body, contains('Short by ₹2,000.00'));
      // Autopay the day before, at 9 am.
      final ap = plan.firstWhere((r) => r.title == 'Netflix autopay tomorrow');
      expect(ap.at, DateTime(2026, 11, 19, 9));
      // The debt the day before it is due.
      expect(titles, contains('Pay back Meera tomorrow'));
      // Sorted by time, and sent to the phone as JSON.
      expect(plan.first.at.isBefore(plan.last.at), isTrue);
      expect((jsonDecode(sent!) as List).length, plan.length);
    },
  );

  test('switched-off kinds are left out', () async {
    await db.settingsDao.set(SettingKeys.remindCards, '0');
    await db.settingsDao.set(SettingKeys.remindAutopay, '0');
    final plan = await replanReminders(db, (_) async {}, now: now);
    expect(plan.map((r) => r.title), ['Pay back Meera tomorrow']);
  });

  test(
    'ids are stable, so re-planning replaces instead of duplicating',
    () async {
      final a = await replanReminders(db, (_) async {}, now: now);
      final b = await replanReminders(
        db,
        (_) async {},
        now: now.add(const Duration(minutes: 5)),
      );
      expect(a.map((r) => r.id), b.map((r) => r.id));
    },
  );
}
