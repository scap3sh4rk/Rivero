import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/reconciliation/balance_reconciler.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';
import 'package:rivero/core/reconciliation/refund_matcher.dart';

/// Provider holding the current Safe-to-Spend amount in minor units (paise).
final safeToSpendProvider = StateProvider<int>((ref) => 4825000); // ₹48,250.00

/// Provider holding total salary credit in minor units (paise).
final salaryRootBalanceProvider = StateProvider<int>(
  (ref) => 15000000,
); // ₹1,50,000.00

/// Provider indicating whether the app is in privacy mode (hiding balances).
final privacyModeProvider = StateProvider<bool>((ref) => false);

/// User's appearance choice. Dark is the default.
enum AppThemeMode { dark, light, system }

final themeModeProvider = StateProvider<AppThemeMode>(
  (ref) => AppThemeMode.dark,
);

/// Waterfall allocator engine instance.
final waterfallAllocatorProvider = Provider<WaterfallAllocator>((ref) {
  return const WaterfallAllocator();
});

/// Safe-to-Spend calculator engine instance.
final safeToSpendCalculatorProvider = Provider<SafeToSpendCalculator>((ref) {
  return const SafeToSpendCalculator();
});

/// User's configured salary credit day of the month (1..31). Defaults to 1st.
final userSalaryDayProvider = StateProvider<int>((ref) => 1);

/// Expected monthly salary in minor units (0 = not configured yet).
final monthlySalaryProvider = StateProvider<int>((ref) => 0);

/// Whether unsettled credit-card spend is reserved out of Safe-to-Spend.
final reserveCreditCardsProvider = StateProvider<bool>((ref) => true);

/// null = still loading, false = needs onboarding, true = ready.
final onboardedProvider = StateProvider<bool?>((ref) => null);

/// Loads persisted settings into providers and saves later changes back.
class SettingsSync {
  SettingsSync(this.ref);
  final Ref ref;

  Future<void> load() async {
    final dao = ref.read(databaseProvider).settingsDao;
    ref.read(userSalaryDayProvider.notifier).state =
        await dao.getInt(SettingKeys.salaryDay) ?? 1;
    ref.read(monthlySalaryProvider.notifier).state =
        await dao.getInt(SettingKeys.monthlySalary) ?? 0;
    ref.read(reserveCreditCardsProvider.notifier).state =
        (await dao.get(SettingKeys.reserveCreditCards)) != '0';
    var onboarded = (await dao.get(SettingKeys.onboarded)) == '1';
    if (!onboarded &&
        (await ref
                .read(databaseProvider)
                .accountsDao
                .getAllActivePhysicalAccounts())
            .isNotEmpty) {
      // Existing install that predates onboarding: don't make them redo setup.
      onboarded = true;
      await dao.set(SettingKeys.onboarded, '1');
    }
    ref.read(onboardedProvider.notifier).state = onboarded;
  }

  /// Persist every change to the three user-editable settings.
  void listen() {
    Future<void> save(String k, String v) =>
        ref.read(databaseProvider).settingsDao.set(k, v);
    ref
      ..listen(
        userSalaryDayProvider,
        (_, v) => save(SettingKeys.salaryDay, '$v'),
      )
      ..listen(
        monthlySalaryProvider,
        (_, v) => save(SettingKeys.monthlySalary, '$v'),
      )
      ..listen(
        reserveCreditCardsProvider,
        (_, v) => save(SettingKeys.reserveCreditCards, v ? '1' : '0'),
      )
      ..listen(onboardedProvider, (_, v) {
        if (v ?? false) save(SettingKeys.onboarded, '1');
      });
  }
}

final settingsSyncProvider = Provider<SettingsSync>(SettingsSync.new);

/// Current active monthly paycycle based on configured salary credit day.
final currentPaycycleProvider = Provider<Paycycle>((ref) {
  final salaryDay = ref.watch(userSalaryDayProvider);
  return Paycycle.fromSalaryDay(salaryCreditDay: salaryDay);
});

/// Preference whether to include pending unreceived reimbursements in Safe-to-Spend.
final includePendingReimbursementsProvider = StateProvider<bool>(
  (ref) => false,
);

/// Central database provider.
///
/// Must be overridden at startup with the encrypted database (see `main`);
/// there is deliberately no plaintext fallback.
final databaseProvider = Provider<RiveroDatabase>((ref) {
  throw StateError('databaseProvider must be overridden with an open database');
});

/// Database seeder provider.
final databaseSeederProvider = Provider<DatabaseSeeder>((ref) {
  final db = ref.watch(databaseProvider);
  return DatabaseSeeder(db);
});

/// Financial parser provider.
final financialParserProvider = Provider<FinancialParser>((ref) {
  return const FinancialParser();
});

/// Deduplication engine provider.
final deduplicationEngineProvider = Provider<DeduplicationEngine>((ref) {
  return const DeduplicationEngine();
});

/// Ingestion service provider coordinating parsing, deduplication, and persistence.
final ingestionServiceProvider = Provider<IngestionService>((ref) {
  final db = ref.watch(databaseProvider);
  final parser = ref.watch(financialParserProvider);
  final deduplicator = ref.watch(deduplicationEngineProvider);
  return IngestionService(
    database: db,
    parser: parser,
    deduplicator: deduplicator,
  );
});

final salaryPlanServiceProvider = Provider<SalaryPlanService>((ref) {
  return SalaryPlanService(ref.watch(databaseProvider));
});

/// A salary credit this cycle that has not been split into buckets yet.
final pendingSalaryProvider = FutureProvider<LedgerTransaction?>((ref) {
  ref.watch(allTransactionsStreamProvider); // re-check when ledger changes
  final cycle = ref.watch(currentPaycycleProvider);
  final expected = ref.watch(monthlySalaryProvider);
  return ref
      .read(salaryPlanServiceProvider)
      .pendingSalary(
        cycleStart: cycle.cycleStartDate,
        expectedSalary: expected,
      );
});

/// Applies balance and budget effects for confirmed transactions.
final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(ref.watch(databaseProvider));
});

/// Internal transfer matcher provider.
final internalTransferMatcherProvider = Provider<InternalTransferMatcher>((
  ref,
) {
  return const InternalTransferMatcher();
});

/// Refund matcher provider.
final refundMatcherProvider = Provider<RefundMatcher>((ref) {
  return const RefundMatcher();
});

/// Balance reconciler provider.
final balanceReconcilerProvider = Provider<BalanceReconciler>((ref) {
  final db = ref.watch(databaseProvider);
  return BalanceReconciler(database: db);
});

/// Reconciliation service provider.
final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final db = ref.watch(databaseProvider);
  final transferMatcher = ref.watch(internalTransferMatcherProvider);
  final refundMatcher = ref.watch(refundMatcherProvider);
  final reconciler = ref.watch(balanceReconcilerProvider);
  return ReconciliationService(
    database: db,
    transferMatcher: transferMatcher,
    refundMatcher: refundMatcher,
    balanceReconciler: reconciler,
  );
});

/// Stream of all active physical accounts.
final activePhysicalAccountsProvider = StreamProvider<List<PhysicalAccount>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.accountsDao.watchActivePhysicalAccounts();
});

/// Stream of all virtual allocation buckets.
final allAllocationBucketsProvider = StreamProvider<List<AllocationBucket>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.accountsDao.watchAllBuckets();
});

/// Stream of recent transactions.
final recentTransactionsProvider = StreamProvider<List<LedgerTransaction>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.transactionsDao.watchRecentTransactions();
});

/// Stream of transactions needing user triage / review.
final pendingReviewTransactionsProvider =
    StreamProvider<List<LedgerTransaction>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.transactionsDao.watchPendingReviewTransactions();
    });

/// Stream of active recurring mandates (UPI Autopay / e-NACH).
final activeMandatesProvider = StreamProvider<List<Mandate>>((ref) {
  return ref.watch(databaseProvider).mandatesDao.watchActiveMandates();
});

/// Stream of all mandates, any status.
final allMandatesProvider = StreamProvider<List<Mandate>>((ref) {
  return ref.watch(databaseProvider).mandatesDao.watchAllMandates();
});

/// Live calculated Safe-to-Spend result dynamically computed from database streams and paycycle.
final liveSafeToSpendResultProvider = Provider<AsyncValue<SafeToSpendResult>>((
  ref,
) {
  final bucketsAsync = ref.watch(allAllocationBucketsProvider);
  final accountsAsync = ref.watch(activePhysicalAccountsProvider);
  final paycycle = ref.watch(currentPaycycleProvider);
  final calculator = ref.watch(safeToSpendCalculatorProvider);
  final includeReimbursements = ref.watch(includePendingReimbursementsProvider);

  if (bucketsAsync.isLoading || accountsAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (bucketsAsync.hasError) {
    return AsyncValue.error(bucketsAsync.error!, bucketsAsync.stackTrace!);
  }
  if (accountsAsync.hasError) {
    return AsyncValue.error(accountsAsync.error!, accountsAsync.stackTrace!);
  }

  final buckets = bucketsAsync.value ?? [];
  final accounts = accountsAsync.value ?? [];
  final reserveCards = ref.watch(reserveCreditCardsProvider);

  // 1. Expense bucket balance
  var expenseBalance = 0;
  for (final b in buckets) {
    if (b.role == AccountRole.expense) {
      expenseBalance += b.allocatedMinorUnits - b.spentMinorUnits;
    }
  }

  // 2. CC liabilities (negative balances on liability accounts)
  var ccLiability = 0;
  for (final acc in accounts) {
    if (reserveCards && acc.isLiability && acc.balanceMinorUnits < 0) {
      ccLiability += acc.balanceMinorUnits.abs();
    }
  }

  // 3. Active mandates due before the cycle ends
  final upcomingMandates = sumUpcomingCommitments(
    ref.watch(activeMandatesProvider).value ?? const [],
    DateTime.now(),
    paycycle.cycleEndDate,
  );

  final result = calculator.calculate(
    expenseBalance: expenseBalance,
    upcomingMandates: upcomingMandates,
    unsettledCreditCardLiability: ccLiability,
    pendingReimbursements: 0,
    daysRemainingInCycle: paycycle.daysRemaining,
    lastSyncedAt: DateTime.now(),
    includePendingReimbursements: includeReimbursements,
  );

  return AsyncValue.data(result);
});

/// Active bottom navigation tab index (0: Overview, 1: Accounts, 2: Budgets, 3: Transactions, 4: Settings).
final selectedNavIndexProvider = StateProvider<int>((ref) => 0);

/// Stream of all transactions across the ledger.
final allTransactionsStreamProvider = StreamProvider<List<LedgerTransaction>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.transactionsDao.watchAllTransactions();
});

/// List of account types (starts with default presets, can hold up to 100 custom types).
final customAccountTypesProvider = StateProvider<List<String>>((ref) {
  return List.from(StandardAccountTypes.defaultList);
});
