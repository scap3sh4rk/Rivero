import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Currencies your accounts use, other than rupees.
Set<String> foreignCurrencies(List<PhysicalAccount> accounts) => {
  for (final a in accounts)
    if (a.currencyCode != homeCurrency) a.currencyCode,
};

/// Settings → Exchange rates: what one unit of each currency is worth in
/// rupees. Typed in, never downloaded (Rivero makes no network calls).
class ExchangeRatesScreen extends ConsumerWidget {
  const ExchangeRatesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ExchangeRatesScreen()));

  static String _rupees(int? paise) => paise == null || paise <= 0
      ? ''
      : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codes = foreignCurrencies(
      ref.watch(activePhysicalAccountsProvider).value ?? const [],
    ).toList()..sort();
    final rates = ref.watch(exchangeRatesProvider);
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Exchange rates',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        children: [
          Text(
            'Totals and Safe to spend are in rupees. Accounts in another '
            'currency are counted at the rate you set here; update it when '
            'it moves.',
            style: RiveroTypography.bodySmall,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          if (codes.isEmpty)
            Text(
              'All your accounts are in rupees. Pick a currency when adding '
              'or editing a bank or cash account.',
              style: RiveroTypography.bodyMedium,
            ),
          for (final c in codes)
            Padding(
              padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
              child: TextFormField(
                key: ValueKey('rate-$c'),
                initialValue: _rupees(rates.paisePerUnit[c]),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: '1 $c in rupees',
                  prefixText: '₹ ',
                  hintText: c == 'USD' ? '83.25' : null,
                ),
                onChanged: (v) {
                  final paise = parseAmountMinorUnits(v.trim());
                  final next = {...rates.paisePerUnit};
                  paise > 0 ? next[c] = paise : next.remove(c);
                  ref.read(exchangeRatesProvider.notifier).state =
                      ExchangeRates(next);
                },
              ),
            ),
        ],
      ),
    );
  }
}
