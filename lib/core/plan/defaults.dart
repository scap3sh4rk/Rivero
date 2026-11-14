import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';

/// What every install needs before the user has added anything: the one
/// everyday-spending category. Accounts, the salary and the other categories
/// come from the user (Accounts tab, Plan), guided by the first-run tour.
Future<void> ensureDefaults(RiveroDatabase db) async {
  // Captured payments wait for the user's Accept or Ignore unless they turn
  // automatic acceptance on.
  if (await db.settingsDao.get(SettingKeys.captureAutoAccept) == null) {
    await db.settingsDao.set(SettingKeys.captureAutoAccept, '0');
  }
  if ((await db.accountsDao.getAllBuckets()).isNotEmpty) return;
  final now = DateTime.now();
  await db.accountsDao.upsertBucket(
    AllocationBucketsCompanion(
      id: const Value('bucket-expense'),
      name: const Value('Monthly Expenses'),
      role: const Value(AccountRole.expense),
      priorityOrder: const Value(1),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}
