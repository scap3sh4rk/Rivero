import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:rivero/core/database/daos/accounts_dao.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/daos/transactions_dao.dart';
import 'package:rivero/core/database/encrypted_connection.dart';
import 'package:rivero/core/database/tables/allocation_buckets_table.dart';
import 'package:rivero/core/database/tables/app_settings_table.dart';
import 'package:rivero/core/database/tables/associated_titles_table.dart';
import 'package:rivero/core/database/tables/dues_table.dart';
import 'package:rivero/core/database/tables/mandates_table.dart';
import 'package:rivero/core/database/tables/physical_accounts_table.dart';
import 'package:rivero/core/database/tables/raw_ingestion_logs_table.dart';
import 'package:rivero/core/database/tables/transactions_table.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

part 'database.g.dart';

/// Central Drift database for Rivero with encrypted SQLite (SQLCipher) support.
@DriftDatabase(
  tables: [
    PhysicalAccounts,
    AllocationBuckets,
    RawIngestionLogs,
    Transactions,
    Mandates,
    AssociatedTitles,
    AppSettings,
    Dues,
  ],
  daos: [
    AccountsDao,
    TransactionsDao,
    MandatesDao,
    IngestionLogsDao,
    SettingsDao,
  ],
)
class RiveroDatabase extends _$RiveroDatabase {
  RiveroDatabase(super.e);

  /// In-memory constructor for unit and integration testing.
  RiveroDatabase.memory() : super(NativeDatabase.memory());

  /// Open an encrypted production database file with the given key.
  factory RiveroDatabase.encrypted(
    String encryptionKey, {
    Directory? directory,
  }) {
    return RiveroDatabase(
      openEncryptedConnection(encryptionKey, directory: directory),
    );
  }

  /// Deletes every row in every table (developer "delete all data").
  Future<void> wipeAll() => transaction(() async {
    // Children before parents (foreign keys).
    await delete(dues).go();
    await delete(transactions).go();
    await delete(mandates).go();
    await delete(rawIngestionLogs).go();
    await delete(allocationBuckets).go();
    await delete(associatedTitles).go();
    await delete(physicalAccounts).go();
    await delete(appSettings).go();
  });

  /// Lookups every screen makes (by date, account, state, plan id prefix).
  Future<void> _createIndexes() async {
    for (final sql in const [
      'CREATE INDEX IF NOT EXISTS idx_txn_time ON transactions (transaction_timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_txn_account ON transactions (physical_account_id, transaction_timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_txn_state ON transactions (transaction_state)',
      'CREATE INDEX IF NOT EXISTS idx_txn_amount ON transactions (amount_minor_units, transaction_timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_logs_status ON raw_ingestion_logs (parse_status, received_at)',
    ]) {
      await customStatement(sql);
    }
  }

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _createIndexes();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(
            physicalAccounts,
            physicalAccounts.creditLimitMinorUnits,
          );
          await m.addColumn(physicalAccounts, physicalAccounts.accountType);
        }
        if (from < 3) {
          await m.createTable(appSettings);
        }
        if (from < 4) {
          await m.addColumn(
            allocationBuckets,
            allocationBuckets.carryOverMinorUnits,
          );
        }
        if (from < 5) {
          await m.createTable(dues);
        }
        if (from < 6) {
          await m.addColumn(physicalAccounts, physicalAccounts.colorValue);
          await m.addColumn(physicalAccounts, physicalAccounts.imagePath);
          await m.addColumn(transactions, transactions.attachmentPath);
        }
        if (from < 7) {
          await m.addColumn(physicalAccounts, physicalAccounts.sortOrder);
        }
        if (from < 8) {
          // Repair: before this version, re-applying a plan inside the same
          // pay cycle counted the old budget as carried-over money again and
          // inflated Safe-to-Spend. Reset those stored values.
          await customStatement(
            'UPDATE allocation_buckets SET carry_over_minor_units = 0',
          );
        }
        if (from < 9) {
          // Set-aside categories used to point at the salary account (as their
          // source). A link now means "money also arrives in this account", so
          // clear the old meaning.
          await customStatement(
            'UPDATE allocation_buckets SET linked_physical_account_id = NULL '
            "WHERE role != 'expense'",
          );
        }
        if (from < 10) await _createIndexes();
        if (from < 12) {
          await m.addColumn(dues, dues.attachmentPath);
          // Money accounts never go below zero.
          await customStatement(
            'UPDATE physical_accounts SET balance_minor_units = 0 '
            'WHERE is_liability = 0 AND balance_minor_units < 0',
          );
        }
        if (from < 11) {
          await m.addColumn(physicalAccounts, physicalAccounts.statementDay);
          await m.addColumn(physicalAccounts, physicalAccounts.paymentDueDay);
          await m.addColumn(dues, dues.dueDate);
        }
        if (from < 13) {
          await m.addColumn(
            physicalAccounts,
            physicalAccounts.billsPaidFromAccountId,
          );
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );
  }
}
