import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/ingestion_result.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/plan/defaults.dart';
import 'package:rivero/core/rules/capture_rules.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final at = DateTime(2026, 11, 14, 10);

  setUp(() async {
    db = RiveroDatabase.memory();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('bank'),
        name: const Value('bank'),
        institution: const Value('Bank'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(5000000),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
    await ensureDefaults(db);
  });
  tearDown(() => db.close());

  Future<IngestionResult> capture(String id, String amount, String ref) =>
      IngestionService(database: db).processNotification(
        RawNotification(
          id: id,
          sender: 'VM-HDFCBK',
          body:
              'Rs $amount debited from A/c XX4012 to VPA swiggy@hdfcbank '
              '(UPI Ref No $ref). Avl bal: Rs 45,000.00',
          receivedAt: at,
        ),
      );

  test(
    'a matching rule sets the category; amount range is respected',
    () async {
      await CaptureRules(db).add(
        const CaptureRule(
          contains: 'SWIGGY',
          category: 'Food',
          maxMinorUnits: 100000,
        ),
      );
      final small = await capture('a', '450.00', '431712345678');
      final big = await capture('b', '2,450.00', '431712345679');
      final s = await db.transactionsDao.getTransactionById(
        small.persistedTransactionId!,
      );
      final b = await db.transactionsDao.getTransactionById(
        big.persistedTransactionId!,
      );
      expect(s!.category, 'Food');
      expect(
        s.transactionState,
        TransactionState.needsReview,
      ); // still reviewed
      expect(b!.category, isNot('Food')); // above ₹1,000: rule does not apply
    },
  );

  test('an ignore rule drops the capture', () async {
    await CaptureRules(db)
        .add(const CaptureRule(contains: 'swiggy', ignore: true));
    final r = await capture('c', '450.00', '431712345670');
    expect(r.status, ParseStatus.ignored);
    expect(r.persistedTransactionId, isNull);
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('suggests a rule after the same payee is filed twice', () async {
    final rules = CaptureRules(db);
    final r1 = await capture('d', '450.00', '431712345671');
    final t1 = (await db.transactionsDao.getTransactionById(
      r1.persistedTransactionId!,
    ))!;
    Future<void> file(String id) =>
        (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
          const TransactionsCompanion(category: Value('Food')),
        );
    await file(t1.id);
    expect(await rules.shouldSuggest(t1.merchant, 'Food'), isFalse);
    final r2 = await capture('e', '120.00', '431712345672');
    await file(r2.persistedTransactionId!);
    expect(await rules.shouldSuggest(t1.merchant, 'Food'), isTrue);
    await rules.add(CaptureRule(contains: t1.merchant, category: 'Food'));
    expect(await rules.shouldSuggest(t1.merchant, 'Food'), isFalse);
  });
}
