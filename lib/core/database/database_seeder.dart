import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Prepopulates the Rivero local SQLite database with initial custodial accounts,
/// virtual allocation buckets, mandates, and sample review transactions on first launch.
class DatabaseSeeder {
  const DatabaseSeeder(this.database);

  final RiveroDatabase database;

  /// Seeds default financial profile if no physical accounts exist.
  Future<void> seedIfEmpty() async {
    final existingAccounts = await database.accountsDao
        .getAllActivePhysicalAccounts();
    if (existingAccounts.isNotEmpty) {
      return; // Already initialized
    }

    final now = DateTime.now();

    // 1. Physical Custodial Accounts
    await database.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('acc-salary'),
        name: const Value('Primary HDFC Salary'),
        institution: const Value('HDFC Bank'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(15000000), // ₹1,50,000
        isActive: const Value(true),
        isLiability: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await database.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('acc-expense'),
        name: const Value('ICICI Daily Expenses'),
        institution: const Value('ICICI Bank'),
        accountMask: const Value('8841'),
        balanceMinorUnits: const Value(4825000), // ₹48,250
        isActive: const Value(true),
        isLiability: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await database.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('acc-cc'),
        name: const Value('ICICI Sapphiro Card'),
        institution: const Value('ICICI Bank'),
        accountMask: const Value('7102'),
        balanceMinorUnits: const Value(-1425000), // -₹14,250 liability
        isActive: const Value(true),
        isLiability: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // 2. Virtual Allocation Buckets
    await database.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('bucket-expense'),
        linkedPhysicalAccountId: const Value('acc-expense'),
        name: const Value('Monthly Expenses'),
        role: const Value(AccountRole.expense),
        targetMinorUnits: const Value(5000000),
        allocatedMinorUnits: const Value(4825000),
        priorityOrder: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await database.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('bucket-invest'),
        linkedPhysicalAccountId: const Value('acc-salary'),
        name: const Value('Mutual Funds & Equity SIP'),
        role: const Value(AccountRole.investment),
        targetMinorUnits: const Value(6000000),
        allocatedMinorUnits: const Value(6000000),
        priorityOrder: const Value(2),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await database.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('bucket-savings'),
        linkedPhysicalAccountId: const Value('acc-salary'),
        name: const Value('Emergency Fund'),
        role: const Value(AccountRole.savings),
        targetMinorUnits: const Value(3000000),
        allocatedMinorUnits: const Value(3000000),
        priorityOrder: const Value(3),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // 3. Active Recurring Mandates (Autopay commitments)
    await database.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: const Value('mandate-netflix'),
        physicalAccountId: const Value('acc-expense'),
        allocationBucketId: const Value('bucket-expense'),
        payee: const Value('Netflix Subscription'),
        amountMinorUnits: const Value(19900), // ₹199.00
        frequency: const Value(MandateFrequency.monthly),
        status: const Value(MandateStatus.active),
        startDate: Value(now.subtract(const Duration(days: 30))),
        nextExecutionDate: Value(now.add(const Duration(days: 5))),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await database.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: const Value('mandate-wifi'),
        physicalAccountId: const Value('acc-expense'),
        allocationBucketId: const Value('bucket-expense'),
        payee: const Value('Airtel Broadband'),
        amountMinorUnits: const Value(99900), // ₹999.00
        frequency: const Value(MandateFrequency.monthly),
        status: const Value(MandateStatus.active),
        startDate: Value(now.subtract(const Duration(days: 30))),
        nextExecutionDate: Value(now.add(const Duration(days: 12))),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    // 4. Sample Pending Review Transactions for the Swiper
    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: const Value('txn-review-1'),
        physicalAccountId: const Value('acc-expense'),
        allocationBucketId: const Value('bucket-expense'),
        amountMinorUnits: const Value(-45000), // -₹450.00
        transactionType: const Value(TransactionType.expense),
        transactionState: const Value(TransactionState.needsReview),
        merchant: const Value('Zomato'),
        category: const Value('Food & Dining'),
        referenceNumber: const Value('UPI/431900123456'),
        transactionTimestamp: Value(now.subtract(const Duration(hours: 2))),
        createdAt: Value(now),
      ),
    );

    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: const Value('txn-review-2'),
        physicalAccountId: const Value('acc-expense'),
        allocationBucketId: const Value('bucket-expense'),
        amountMinorUnits: const Value(-34000), // -₹340.00
        transactionType: const Value(TransactionType.expense),
        transactionState: const Value(TransactionState.needsReview),
        merchant: const Value('Uber'),
        category: const Value('Transportation'),
        referenceNumber: const Value('UPI/431900888999'),
        transactionTimestamp: Value(now.subtract(const Duration(hours: 5))),
        createdAt: Value(now),
      ),
    );

    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: const Value('txn-review-3'),
        physicalAccountId: const Value('acc-expense'),
        allocationBucketId: const Value('bucket-expense'),
        amountMinorUnits: const Value(-68000), // -₹680.00
        transactionType: const Value(TransactionType.expense),
        transactionState: const Value(TransactionState.needsReview),
        merchant: const Value('Blinkit'),
        category: const Value('Groceries'),
        referenceNumber: const Value('UPI/431900777111'),
        transactionTimestamp: Value(now.subtract(const Duration(hours: 8))),
        createdAt: Value(now),
      ),
    );
  }
}
