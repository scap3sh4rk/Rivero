import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/account_group.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/log_category.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/engine/sts_breakdown.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/defaults.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';
import 'package:rivero/core/reconciliation/refund_matcher.dart';
import 'package:rivero/core/security/app_lock.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/look.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Provider indicating whether the app is in privacy mode (hiding balances).
final privacyModeProvider = StateProvider<bool>((ref) => false);

/// User's appearance choice. Dark is the default.
enum AppThemeMode { dark, light, system }

final themeModeProvider = StateProvider<AppThemeMode>(
  (ref) => AppThemeMode.dark,
);

/// User's configured salary credit day of the month (1..31). Defaults to 1st.
final userSalaryDayProvider = StateProvider<int>((ref) => 1);

/// Expected monthly salary in minor units (0 = not configured yet).
final monthlySalaryProvider = StateProvider<int>((ref) => 0);

/// Appearance: accent, background, weight, sizes... (Settings > Appearance).
final lookProvider = StateProvider<Look>((ref) => const Look());

/// Accounts whose balance is masked (tap the eye on an account to toggle).
final hiddenBalancesProvider = StateProvider<Set<String>>((ref) => const {});

/// Accounts page sections: their order and which are folded.
final accountGroupPrefsProvider = StateProvider<AccountGroupPrefs>(
  (ref) => const AccountGroupPrefs(),
);

/// Home cards the user picked, in order (names; null = the defaults).
final homeWidgetsProvider = StateProvider<List<String>?>((ref) => null);

/// Pictures the user added per bank (BankIcons.key -> file path).
final bankIconsProvider = StateProvider<Map<String, String>>((ref) => const {});

/// Show the net worth card on Accounts.
final showNetWorthProvider = StateProvider<bool>((ref) => true);

/// Money formatting for one account: dots when its balance is hidden
/// (or privacy mode is on).
final accountMoneyMaskProvider =
    Provider<String Function(int) Function(String accountId)>((ref) {
      final privacy = ref.watch(privacyModeProvider);
      final hidden = ref.watch(hiddenBalancesProvider);
      return (id) =>
          (v) => privacy || hidden.contains(id)
          ? '••••'
          : CurrencyFormatter.format(v);
    });

/// Money in the spending account Safe to spend leaves alone (paise).
final keepUntouchedProvider = StateProvider<int>((ref) => 0);

/// Whether unsettled credit-card spend is reserved out of Safe-to-Spend.
final reserveCreditCardsProvider = StateProvider<bool>((ref) => true);

/// null = still loading, true = ready (there is no setup wizard).
final onboardedProvider = StateProvider<bool?>((ref) => null);

/// Confident captures count straight away (otherwise each waits for Accept).
final captureAutoAcceptProvider = StateProvider<bool>((ref) => false);

/// The first-run tour has not been completed yet.
final tourPendingProvider = StateProvider<bool>((ref) => false);

/// Package name of the UPI app the user pays with most (null = not chosen,
/// empty = none).
final primaryUpiProvider = StateProvider<String?>((ref) => null);

/// Its display name (remembered so the row shows it without a lookup).
final primaryUpiNameProvider = StateProvider<String?>((ref) => null);

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
    ref.read(keepUntouchedProvider.notifier).state =
        await dao.getInt(SettingKeys.keepUntouched) ?? 0;
    ref.read(lookProvider.notifier).state = Look.fromJson(
      await dao.get(SettingKeys.look),
    );
    ref.read(accountGroupPrefsProvider.notifier).state =
        AccountGroupPrefs.fromJson(await dao.get(SettingKeys.accountGroups));
    final icons = await dao.get(SettingKeys.bankIcons);
    if (icons != null) {
      try {
        ref.read(bankIconsProvider.notifier).state = (jsonDecode(icons) as Map)
            .cast<String, String>();
      } on FormatException {
        // Unreadable: initials instead.
      }
    }
    final homeWidgets = await dao.get(SettingKeys.homeWidgets);
    if (homeWidgets != null) {
      try {
        ref.read(homeWidgetsProvider.notifier).state = [
          for (final n in jsonDecode(homeWidgets) as List) n as String,
        ];
      } on FormatException {
        // Unreadable: the default cards.
      }
    }
    ref.read(showNetWorthProvider.notifier).state =
        (await dao.get(SettingKeys.showNetWorth)) != '0';
    final hidden = await dao.get(SettingKeys.hiddenBalances);
    if (hidden != null) {
      try {
        ref.read(hiddenBalancesProvider.notifier).state = {
          for (final id in jsonDecode(hidden) as List) id as String,
        };
      } on FormatException {
        // Unreadable: show every balance.
      }
    }
    ref.read(reserveCreditCardsProvider.notifier).state =
        (await dao.get(SettingKeys.reserveCreditCards)) != '0';
    ref.read(salaryAccountIdProvider.notifier).state = await dao.get(
      SettingKeys.salaryAccount,
    );
    final font = await dao.get(SettingKeys.font);
    if (font != null && RiveroFonts.families.contains(font)) {
      ref.read(fontFamilyProvider.notifier).state = font;
    }
    ref.read(lastLogAccountProvider.notifier).state = await dao.get(
      SettingKeys.lastLogAccount,
    );
    ref.read(appLockEnabledProvider.notifier).state =
        (await dao.get(SettingKeys.appLock)) == '1';
    ref.read(exchangeRatesProvider.notifier).state = ExchangeRates.fromJson(
      await dao.get(SettingKeys.exchangeRates),
    );
    final catsJson = await dao.get(SettingKeys.logCategories);
    if (catsJson != null) {
      ref.read(logCategoriesProvider.notifier).state = [
        for (final j in jsonDecode(catsJson) as List)
          LogCategory.fromJson(j as Map<String, dynamic>),
      ];
    }
    // The notification popup offers the same categories as Log.
    await NotificationBridge.setCategories([
      for (final c in ref.read(logCategoriesProvider)) c.name,
    ]);
    final typesJson = await dao.get(SettingKeys.accountTypes);
    if (typesJson != null) {
      ref.read(customAccountTypesProvider.notifier).state =
          (jsonDecode(typesJson) as List).cast<String>();
    }
    ref.read(includePendingReimbursementsProvider.notifier).state =
        (await dao.get(SettingKeys.countOwed)) == '1';
    ref.read(showNegativeStsProvider.notifier).state =
        (await dao.get(SettingKeys.showNegativeSts)) == '1';
    ref.read(openOnLogProvider.notifier).state =
        (await dao.get(SettingKeys.openOnLog)) == '1';
    // No setup wizard: the app opens straight away, with a guided tour
    // the first time. Everything else is added by the user in place.
    await ensureDefaults(ref.read(databaseProvider));
    await dao.set(SettingKeys.onboarded, '1');
    ref.read(tourPendingProvider.notifier).state =
        (await dao.get(SettingKeys.tourDone)) != '1';
    ref.read(captureAutoAcceptProvider.notifier).state =
        (await dao.get(SettingKeys.captureAutoAccept)) == '1';
    ref.read(primaryUpiNameProvider.notifier).state = await dao.get(
      SettingKeys.primaryUpiName,
    );
    final upi = await dao.get(SettingKeys.primaryUpi);
    ref.read(primaryUpiProvider.notifier).state = upi;
    await NotificationBridge.setPrimaryApp(upi);
    ref.read(onboardedProvider.notifier).state = true;
  }

  /// Persist every change to the three user-editable settings.
  void listen() {
    Future<void> save(String k, String v) =>
        ref.read(databaseProvider).settingsDao.set(k, v);
    ref
      ..listen(userSalaryDayProvider, (old, v) async {
        await save(SettingKeys.salaryDay, '$v');
        // Moving pay day keeps this month's plan as this month's plan.
        if (old != null && old != v) {
          final today = ref.read(todayProvider);
          await ref
              .read(salaryPlanServiceProvider)
              .moveCycle(
                from: Paycycle.fromSalaryDay(
                  salaryCreditDay: old,
                  asOf: today,
                ).cycleStartDate,
                to: Paycycle.fromSalaryDay(
                  salaryCreditDay: v,
                  asOf: today,
                ).cycleStartDate,
              );
        }
      })
      ..listen(
        monthlySalaryProvider,
        (_, v) => save(SettingKeys.monthlySalary, '$v'),
      )
      ..listen(
        keepUntouchedProvider,
        (_, v) => save(SettingKeys.keepUntouched, '$v'),
      )
      ..listen(lookProvider, (_, v) => save(SettingKeys.look, v.toJson()))
      ..listen(
        accountGroupPrefsProvider,
        (_, v) => save(SettingKeys.accountGroups, v.toJson()),
      )
      ..listen(
        bankIconsProvider,
        (_, v) => save(SettingKeys.bankIcons, jsonEncode(v)),
      )
      ..listen(homeWidgetsProvider, (_, v) {
        if (v != null) save(SettingKeys.homeWidgets, jsonEncode(v));
      })
      ..listen(
        showNetWorthProvider,
        (_, v) => save(SettingKeys.showNetWorth, v ? '1' : '0'),
      )
      ..listen(
        hiddenBalancesProvider,
        (_, v) => save(SettingKeys.hiddenBalances, jsonEncode(v.toList())),
      )
      ..listen(
        reserveCreditCardsProvider,
        (_, v) => save(SettingKeys.reserveCreditCards, v ? '1' : '0'),
      )
      ..listen(fontFamilyProvider, (_, v) => save(SettingKeys.font, v))
      ..listen(salaryAccountIdProvider, (_, v) {
        if (v != null) save(SettingKeys.salaryAccount, v);
      })
      ..listen(lastLogAccountProvider, (_, v) {
        if (v != null) save(SettingKeys.lastLogAccount, v);
      })
      ..listen(
        appLockEnabledProvider,
        (_, v) => save(SettingKeys.appLock, v ? '1' : '0'),
      )
      ..listen(
        exchangeRatesProvider,
        (_, v) => save(SettingKeys.exchangeRates, v.toJson()),
      )
      ..listen(logCategoriesProvider, (_, v) {
        save(
          SettingKeys.logCategories,
          jsonEncode([for (final c in v) c.toJson()]),
        );
        NotificationBridge.setCategories([for (final c in v) c.name]);
      })
      ..listen(
        customAccountTypesProvider,
        (_, v) => save(SettingKeys.accountTypes, jsonEncode(v)),
      )
      ..listen(
        includePendingReimbursementsProvider,
        (_, v) => save(SettingKeys.countOwed, v ? '1' : '0'),
      )
      ..listen(
        showNegativeStsProvider,
        (_, v) => save(SettingKeys.showNegativeSts, v ? '1' : '0'),
      )
      ..listen(
        openOnLogProvider,
        (_, v) => save(SettingKeys.openOnLog, v ? '1' : '0'),
      )
      ..listen(
        captureAutoAcceptProvider,
        (_, v) => save(SettingKeys.captureAutoAccept, v ? '1' : '0'),
      )
      ..listen(primaryUpiNameProvider, (_, v) {
        if (v != null) save(SettingKeys.primaryUpiName, v);
      })
      ..listen(primaryUpiProvider, (_, v) {
        if (v == null) return;
        save(SettingKeys.primaryUpi, v);
        NotificationBridge.setPrimaryApp(v);
      });
  }
}

final settingsSyncProvider = Provider<SettingsSync>(SettingsSync.new);

/// Current active monthly paycycle based on configured salary credit day.
///
/// Recomputed when the day changes ([todayProvider]) and when a salary that
/// arrived early has been split for the coming cycle.
final currentPaycycleProvider = Provider<Paycycle>((ref) {
  final salaryDay = ref.watch(userSalaryDayProvider);
  final today = ref.watch(todayProvider);
  final normal = Paycycle.fromSalaryDay(
    salaryCreditDay: salaryDay,
    asOf: today,
  );
  final planned = ref.watch(plannedCycleStartProvider).value;
  if (planned != null &&
      !planned.isBefore(normal.nextCycleStartDate) &&
      planned.difference(today).inDays <= 5) {
    return Paycycle.startedEarly(
      salaryCreditDay: salaryDay,
      plannedStart: planned,
      asOf: today,
    );
  }
  return normal;
});

/// Today's date; refreshed at midnight and whenever the app comes back, so
/// days-to-payday never goes stale while the app stays open.
final todayProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Start of the cycle the latest plan was applied for.
final plannedCycleStartProvider = StreamProvider<DateTime?>((ref) {
  final db = ref.watch(databaseProvider);
  return db.settingsDao
      .watch(SettingKeys.lastPlannedCycleStart)
      .map((v) => v == null ? null : DateTime.tryParse(v));
});

/// Show a Safe-to-spend shortfall as a negative amount instead of zero.
final showNegativeStsProvider = StateProvider<bool>((ref) => false);

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
///
/// The user's primary UPI app is always trusted as a payment source, so its
/// notifications are recognised even when it is not a known bank or app.
final financialParserProvider = Provider<FinancialParser>((ref) {
  final primary = ref.watch(primaryUpiProvider);
  if (primary == null || primary.isEmpty) return const FinancialParser();
  return FinancialParser(
    dltValidator: TraiDltValidator(extraPackages: {primary}),
  );
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

final planTransferServiceProvider = Provider<PlanTransferService>((ref) {
  return PlanTransferService(ref.watch(databaseProvider));
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

/// A new pay cycle began and its salary has not been split yet.
final awaitingSalaryProvider = FutureProvider<bool>((ref) {
  ref.watch(allAllocationBucketsProvider); // re-check after a plan is applied
  final cycle = ref.watch(currentPaycycleProvider);
  return ref
      .read(salaryPlanServiceProvider)
      .awaitingSalary(cycle.cycleStartDate);
});

final duesServiceProvider = Provider<DuesService>((ref) {
  return DuesService(ref.watch(databaseProvider));
});

/// Everything owed to the user (split bills, money lent), newest first.
final duesProvider = StreamProvider<List<Due>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.dues,
  )..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).watch();
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

/// Reconciliation service provider.
final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final db = ref.watch(databaseProvider);
  final transferMatcher = ref.watch(internalTransferMatcherProvider);
  final refundMatcher = ref.watch(refundMatcherProvider);
  return ReconciliationService(
    database: db,
    transferMatcher: transferMatcher,
    refundMatcher: refundMatcher,
  );
});

/// Stream of all active physical accounts.
final activePhysicalAccountsProvider = StreamProvider<List<PhysicalAccount>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.accountsDao.watchActivePhysicalAccounts().map((accounts) {
    // The notification popup offers the same accounts (no balances).
    NotificationBridge.setAccounts(accounts);
    return accounts;
  });
});

/// Stream of all virtual allocation buckets.
final allAllocationBucketsProvider = StreamProvider<List<AllocationBucket>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.accountsDao.watchAllBuckets();
});

/// Stream of transactions needing user triage / review.
final pendingReviewTransactionsProvider =
    StreamProvider<List<LedgerTransaction>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.transactionsDao.watchPendingReviewTransactions();
    });

/// The last notifications Rivero received and what it did with each.
final recentCaptureLogsProvider = StreamProvider<List<RawIngestionLog>>((ref) {
  return ref
      .watch(databaseProvider)
      .ingestionLogsDao
      .watchRecentLogs(limit: 60);
});

/// Bank messages Rivero could not read (see IngestionLogsDao.watchUnreadable).
final unreadableMessagesProvider = StreamProvider<List<RawIngestionLog>>((ref) {
  return ref.watch(databaseProvider).ingestionLogsDao.watchUnreadable();
});

/// Stream of active recurring mandates (UPI Autopay / e-NACH).
final activeMandatesProvider = StreamProvider<List<Mandate>>((ref) {
  return ref.watch(databaseProvider).mandatesDao.watchActiveMandates();
});

/// Stream of all mandates, any status.
final allMandatesProvider = StreamProvider<List<Mandate>>((ref) {
  return ref.watch(databaseProvider).mandatesDao.watchAllMandates();
});

/// Safe-to-Spend with every input visible (see [StsBreakdown]).
final stsBreakdownProvider = Provider<AsyncValue<StsBreakdown>>((ref) {
  final bucketsAsync = ref.watch(allAllocationBucketsProvider);
  final accountsAsync = ref.watch(activePhysicalAccountsProvider);
  if (bucketsAsync.isLoading || accountsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (bucketsAsync.hasError) {
    return AsyncValue.error(bucketsAsync.error!, bucketsAsync.stackTrace!);
  }
  if (accountsAsync.hasError) {
    return AsyncValue.error(accountsAsync.error!, accountsAsync.stackTrace!);
  }
  final accounts = accountsAsync.value ?? const <PhysicalAccount>[];
  final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];

  // How fresh the figures are: the newest recorded entry (captured, typed
  // in, or a balance update). Renaming an account is not fresh data. With
  // no entries yet, the balances are as fresh as the accounts' creation.
  DateTime? synced;
  for (final t in txns) {
    if (synced == null || t.createdAt.isAfter(synced)) synced = t.createdAt;
  }
  if (synced == null) {
    for (final a in accounts) {
      if (synced == null || a.createdAt.isAfter(synced)) synced = a.createdAt;
    }
  }

  final cycle = ref.watch(currentPaycycleProvider);
  final awaiting = ref.watch(awaitingSalaryProvider).value ?? false;
  final salaryIn = ref.watch(pendingSalaryProvider).value != null;

  return AsyncValue.data(
    StsBreakdown.compute(
      buckets: bucketsAsync.value ?? const [],
      accounts: ref.watch(exchangeRatesProvider).inHome(accounts),
      mandates: ref.watch(activeMandatesProvider).value ?? const [],
      dues: ref.watch(duesProvider).value ?? const [],
      salaryAccountId: ref.watch(salaryAccountIdProvider),
      pending: [
        for (final t in txns)
          if (t.transactionState == TransactionState.needsReview) t,
      ],
      // New cycle, salary in, not split yet: last cycle's "paid" marks on
      // rent and the like no longer hold.
      paidMarksStale: awaiting && salaryIn,
      // The first days of a cycle whose salary has not landed: the money
      // left has to last until it does (a week in, it is simply late or
      // not tracked, and the month is counted as usual).
      salaryDueNow: awaiting && !salaryIn && cycle.elapsedDays <= 5,
      keepUntouched: ref.watch(keepUntouchedProvider),
      cycle: cycle,
      reserveCards: ref.watch(reserveCreditCardsProvider),
      includeOwed: ref.watch(includePendingReimbursementsProvider),
      lastSyncedAt: synced,
    ),
  );
});

/// Bank, wallet and cash accounts whose balance is out of date: since the
/// user last stated it, a payment was larger than what Rivero thought the
/// account held (it stopped at zero). Usually a missed credit (no message
/// came for it); only the user knows the real figure, so they are asked.
final balanceToUpdateProvider = Provider<Set<String>>((ref) {
  final accounts = ref.watch(activePhysicalAccountsProvider).value ?? const [];
  final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
  final byId = {for (final a in accounts) a.id: a};
  return {
    for (final t in txns)
      if (byId[t.physicalAccountId] case final a?)
        if (!a.isLiability &&
            t.amountMinorUnits < 0 &&
            t.appliedMinorUnits != null &&
            t.appliedMinorUnits! > t.amountMinorUnits &&
            (a.balanceAsOf == null ||
                !t.transactionTimestamp.isBefore(a.balanceAsOf!)))
          a.id,
  };
});

/// Live calculated Safe-to-Spend result.
final liveSafeToSpendResultProvider = Provider<AsyncValue<SafeToSpendResult>>((
  ref,
) {
  return ref.watch(stsBreakdownProvider).whenData((b) => b.result);
});

/// Active tab: 0 Accounts, 1 Plan, 2 Home (centre, default), 3 Log, 4 Activity.
final selectedNavIndexProvider = StateProvider<int>((ref) => 2);

/// Text to start the Log screen with (from a bank message Rivero could not
/// read): the amount it found, a note, and whether money came in.
class LogPrefill {
  const LogPrefill({
    required this.amountText,
    required this.note,
    this.income = false,
    this.category,
    this.accountId,
  });

  /// Best guess from a raw message: the first amount that follows Rs / INR /
  /// ₹ or "debited/credited by|for|with", else the first decimal number.
  factory LogPrefill.fromMessage(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final m =
        RegExp(
          r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
          caseSensitive: false,
        ).firstMatch(clean) ??
        RegExp(
          r'(?:debited|credited|paid|sent|received)\s+(?:by|for|with|of)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
          caseSensitive: false,
        ).firstMatch(clean);
    var amount = (m?.group(1) ?? '').replaceAll(',', '');
    if (amount.endsWith('.0') || amount.endsWith('.00')) {
      amount = amount.substring(0, amount.indexOf('.'));
    }
    final income =
        RegExp(
          r'\b(?:credited|received|deposited|refund)',
          caseSensitive: false,
        ).hasMatch(clean) &&
        !RegExp(r'\bdebited', caseSensitive: false).hasMatch(clean);
    return LogPrefill(
      amountText: amount,
      // The bank's text is not a note: the user adds one if they want.
      note: '',
      income: income,
    );
  }

  /// Rupees as typed on the keypad ("450" or "450.5"); empty if none found.
  final String amountText;
  final String note;
  final bool income;

  /// Picked on the message's notification, if anything was.
  final String? category;

  /// The account picked on the message's notification, if any.
  final String? accountId;

  /// The same, with what was chosen on the notification ([choice] holds
  /// "category", "note" and "account", any may be null).
  LogPrefill withChoice(Map<String, dynamic>? choice) {
    final c = choice?['category'] as String?;
    final n = (choice?['note'] as String?)?.trim();
    final a = choice?['account'] as String?;
    return LogPrefill(
      amountText: amountText,
      note: n == null || n.isEmpty ? note : n,
      income: income,
      category: c == null || c.isEmpty ? category : c,
      accountId: a == null || a.isEmpty ? accountId : a,
    );
  }
}

/// Set by "Add it" on a message Rivero could not read; the Log screen takes
/// it (and clears it) when it opens.
final logPrefillProvider = StateProvider<LogPrefill?>((ref) => null);

/// A captured payment to open in the quick-add sheet (from "Open Rivero"
/// on its notification). MainScreen shows it and clears this.
final openCaptureProvider = StateProvider<String?>((ref) => null);

/// When data was last backed up (manual or automatic), or null.
final lastBackupProvider = StreamProvider<DateTime?>((ref) {
  return ref
      .watch(databaseProvider)
      .settingsDao
      .watch(SettingKeys.lastBackupAt)
      .map((v) => v == null ? null : DateTime.tryParse(v));
});

/// Last account used on the quick-log keypad.
final lastLogAccountProvider = StateProvider<String?>((ref) => null);

/// The user's spending categories (with colours), in their order.
/// The user's exchange rates to rupees (only needed for non-₹ accounts).
final exchangeRatesProvider = StateProvider<ExchangeRates>(
  (ref) => const ExchangeRates({}),
);

/// Converts an amount on an account to rupees (as-is for ₹ accounts).
final toHomeProvider = Provider<int Function(String accountId, int minor)>((
  ref,
) {
  final rates = ref.watch(exchangeRatesProvider);
  final code = {
    for (final a
        in ref.watch(activePhysicalAccountsProvider).value ??
            const <PhysicalAccount>[])
      a.id: a.currencyCode,
  };
  return (id, minor) => rates.toHome(minor, code[id] ?? homeCurrency);
});

final logCategoriesProvider = StateProvider<List<LogCategory>>(
  (ref) => LogCategory.defaults,
);

/// The account salary lands in (null = pick automatically).
final salaryAccountIdProvider = StateProvider<String?>((ref) => null);

/// The app's typeface (one of RiveroFonts.families).
final fontFamilyProvider = StateProvider<String>(
  (ref) => RiveroFonts.families.first,
);

/// Open the app on the quick-log keypad instead of Home.
final openOnLogProvider = StateProvider<bool>((ref) => false);

/// What the home-screen widget shows: Safe to spend per day (the same
/// number as the Home card) and a short caption. Amounts are hidden when
/// the app hides them or App lock is on (the widget sits outside the lock).
final homeWidgetTextProvider = Provider<({String amount, String caption})?>((
  ref,
) {
  final sts = ref.watch(liveSafeToSpendResultProvider).value;
  final breakdown = ref.watch(stsBreakdownProvider).value;
  if (sts == null) return null;
  final hasPlan = breakdown?.hasPlan ?? true;
  final showNegative = ref.watch(showNegativeStsProvider);
  final value = sts.isDeficit
      ? (showNegative && hasPlan ? sts.effectiveSafeToSpend : 0)
      : sts.dailySpendingPace;
  final hidden =
      ref.watch(privacyModeProvider) || ref.watch(appLockEnabledProvider);
  final awaiting = ref.watch(awaitingSalaryProvider).value ?? false;
  final days = ref.watch(currentPaycycleProvider).daysRemaining;
  return (
    amount: hidden
        ? '₹••••'
        : CurrencyFormatter.format(value, includeDecimals: false),
    caption: !hasPlan
        ? 'Set up your plan in Rivero'
        : awaiting
        ? 'Waiting for salary'
        : '$days ${days == 1 ? 'day' : 'days'} to payday',
  );
});

/// A bill scan to start when Log opens (from the launcher shortcut).
final pendingScanProvider = StateProvider<bool>((ref) => false);

/// Each card's current bill (what its last statement still asks for), in
/// the home currency. Refreshes with the ledger and at midnight.
final cardBillsProvider = Provider<Map<String, CardBill>>((ref) {
  return CardBill.of(
    accounts: ref.watch(activePhysicalAccountsProvider).value ?? const [],
    transactions: ref.watch(allTransactionsStreamProvider).value ?? const [],
    now: ref.watch(todayProvider),
    rates: ref.watch(exchangeRatesProvider),
  );
});

/// Stream of all transactions across the ledger.
final allTransactionsStreamProvider = StreamProvider<List<LedgerTransaction>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final stream = db.transactionsDao.watchAllTransactions();
  // Entries just deleted are hidden at once, while their Undo is offered.
  final hidden = ref.watch(pendingRemovalsProvider);
  return hidden.isEmpty
      ? stream
      : stream.map(
          (all) => [
            for (final t in all)
              if (!hidden.contains(t.id)) t,
          ],
        );
});

/// Entries the user just deleted: hidden everywhere at once, and deleted for
/// real only when their Undo is no longer offered (see deleteWithUndo).
final pendingRemovalsProvider = StateProvider<Set<String>>((ref) => const {});

/// List of account types (starts with default presets, can hold up to 100 custom types).
final customAccountTypesProvider = StateProvider<List<String>>((ref) {
  return List.from(StandardAccountTypes.defaultList);
});
