import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/reconciliation/balance_reconciler.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';
import 'package:rivero/core/reconciliation/refund_matcher.dart';

/// Provider holding the current Safe-to-Spend amount in minor units (paise).
/// Initial baseline provider for Phase 1.
final safeToSpendProvider = StateProvider<int>((ref) => 4825000); // ₹48,250.00

/// Provider holding total salary credit in minor units (paise).
final salaryRootBalanceProvider = StateProvider<int>(
  (ref) => 15000000,
); // ₹1,50,000.00

/// Provider indicating whether the app is in privacy mode (hiding balances).
final privacyModeProvider = StateProvider<bool>((ref) => false);

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
final databaseProvider = Provider<RiveroDatabase>((ref) {
  final db = RiveroDatabase();
  ref.onDispose(db.close);
  return db;
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
