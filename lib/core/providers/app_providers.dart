import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider holding the current Safe-to-Spend amount in minor units (paise).
/// Initial baseline provider for Phase 1.
final safeToSpendProvider = StateProvider<int>((ref) => 4825000); // ₹48,250.00

/// Provider holding total salary credit in minor units (paise).
final salaryRootBalanceProvider = StateProvider<int>(
  (ref) => 15000000,
); // ₹1,50,000.00

/// Provider indicating whether the app is in privacy mode (hiding balances).
final privacyModeProvider = StateProvider<bool>((ref) => false);
