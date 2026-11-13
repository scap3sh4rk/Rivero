import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() async {
    db = RiveroDatabase.memory();

    final now = DateTime.now();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('acc-01'),
        name: const Value('HDFC Bank'),
        institution: const Value('HDFC'),
        accountMask: const Value('••4012'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('MandatesDao tests', () {
    test('calculate upcoming commitment sums', () async {
      final now = DateTime.now();
      final dueIn5Days = now.add(const Duration(days: 5));
      final dueIn12Days = now.add(const Duration(days: 12));
      final dueIn40Days = now.add(const Duration(days: 40));

      // Mandate 1: Netflix ₹649.00 due in 5 days
      await db.mandatesDao.upsertMandate(
        MandatesCompanion(
          id: const Value('mandate-01'),
          payee: const Value('Netflix'),
          amountMinorUnits: const Value(64900),
          frequency: const Value(MandateFrequency.monthly),
          physicalAccountId: const Value('acc-01'),
          startDate: Value(now),
          nextExecutionDate: Value(dueIn5Days),
          status: const Value(MandateStatus.active),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Mandate 2: SIP ₹5,000.00 due in 12 days
      await db.mandatesDao.upsertMandate(
        MandatesCompanion(
          id: const Value('mandate-02'),
          payee: const Value('SIP - Nippon India'),
          amountMinorUnits: const Value(500000),
          frequency: const Value(MandateFrequency.monthly),
          physicalAccountId: const Value('acc-01'),
          startDate: Value(now),
          nextExecutionDate: Value(dueIn12Days),
          status: const Value(MandateStatus.active),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Mandate 3: Far future mandate due in 40 days (outside 30-day cycle)
      await db.mandatesDao.upsertMandate(
        MandatesCompanion(
          id: const Value('mandate-03'),
          payee: const Value('Annual Insurance'),
          amountMinorUnits: const Value(1200000),
          frequency: const Value(MandateFrequency.annual),
          physicalAccountId: const Value('acc-01'),
          startDate: Value(now),
          nextExecutionDate: Value(dueIn40Days),
          status: const Value(MandateStatus.active),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Total commitment for the next 20 days (should include Netflix and SIP = 564900 paise = ₹5,649.00)
      final commitment = await db.mandatesDao
          .calculateUpcomingCommitmentMinorUnits(
            now.add(const Duration(days: 20)),
          );
      expect(commitment, equals(564900));

      // Pause Netflix mandate and re-calculate
      await db.mandatesDao.updateMandateStatus(
        'mandate-01',
        MandateStatus.paused,
      );
      final commitmentAfterPause = await db.mandatesDao
          .calculateUpcomingCommitmentMinorUnits(
            now.add(const Duration(days: 20)),
          );
      expect(commitmentAfterPause, equals(500000)); // Only SIP
    });
  });
}
