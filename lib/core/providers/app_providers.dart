import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';

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
