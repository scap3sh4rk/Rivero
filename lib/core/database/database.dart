import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rivero/core/database/daos/accounts_dao.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/daos/transactions_dao.dart';
import 'package:rivero/core/database/tables/allocation_buckets_table.dart';
import 'package:rivero/core/database/tables/associated_titles_table.dart';
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
  ],
  daos: [AccountsDao, TransactionsDao, MandatesDao, IngestionLogsDao],
)
class RiveroDatabase extends _$RiveroDatabase {
  RiveroDatabase([QueryExecutor? e]) : super(e ?? _openDefaultConnection());

  /// In-memory constructor for unit and integration testing.
  RiveroDatabase.memory() : super(NativeDatabase.memory());

  /// Open an encrypted production database file with the given key.
  factory RiveroDatabase.encrypted(String encryptionKey) {
    return RiveroDatabase(_openEncryptedConnection(encryptionKey));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );
  }

  static LazyDatabase _openDefaultConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'rivero_unencrypted.db'));
      return NativeDatabase(file);
    });
  }

  static LazyDatabase _openEncryptedConnection(String encryptionKey) {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'rivero_encrypted.db'));
      return NativeDatabase(
        file,
        setup: (rawDb) {
          // SQLCipher PRAGMA key execution
          rawDb
            ..execute("PRAGMA key = '$encryptionKey';")
            ..execute('PRAGMA cipher_memory_security = ON;');
        },
      );
    });
  }
}
