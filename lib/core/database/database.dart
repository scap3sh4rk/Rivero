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

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
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
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );
  }
}
