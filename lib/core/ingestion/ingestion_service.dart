import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ingestion/models/ingestion_result.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ingestion/parser/message_intent.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';
import 'package:rivero/core/rules/capture_rules.dart';
import 'package:uuid/uuid.dart';

/// Central ingestion orchestrator coordinating the audit trail,
/// regex financial parser, deduplication engine, and ledger persistence.
class IngestionService {
  IngestionService({
    required this.database,
    this.parser = const FinancialParser(),
    this.deduplicator = const DeduplicationEngine(),
    this.uuid = const Uuid(),
  });

  final RiveroDatabase database;
  final FinancialParser parser;
  final DeduplicationEngine deduplicator;
  final Uuid uuid;

  /// Ingests and processes a [RawNotification] through the end-to-end pipeline.
  Future<IngestionResult> processNotification(
    RawNotification notification,
  ) async {
    final now = DateTime.now();
    final logId = notification.id.isNotEmpty ? notification.id : uuid.v4();

    // 0. Non-transactions (OTP, pre-debit reminders, mandate lifecycle,
    // statement notices) never reach the ledger.
    final intent = parser.classify(notification.body);
    if (intent != MessageIntent.transaction) {
      return await _handleNotice(notification, intent, logId, now);
    }

    // 1. Attempt parsing
    final parsed = parser.parse(notification);

    if (parsed == null) {
      // Failed to parse financial details
      await database.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: Value(logId),
          sourceChannel: Value(notification.channel),
          senderHeader: Value(_sender(notification)),
          sourcePackage: Value(notification.packageName),
          rawPayload: Value(notification.body),
          receivedAt: Value(notification.receivedAt),
          parseStatus: const Value(ParseStatus.failed),
          confidenceScore: const Value(0),
          failureReason: const Value(IngestionLogsDao.unreadable),
          createdAt: Value(now),
        ),
      );

      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.failed,
        isDuplicate: false,
        failureReason: 'No recognizable financial entities found',
      );
    }

    // 2. An unsure message with neither an account number nor a reference
    // is almost always a promotion ("Get Rs 500 cashback, pay now"): log it
    // as unreadable instead of asking the user about it.
    // Payment apps (PhonePe, GPay...) leave both out of their own
    // notifications, so they are exempt.
    final fromPaymentApp = parser.dltValidator.isFinancialSender(
      senderHeader: notification.sender,
      packageName: notification.packageName,
    );
    if (!fromPaymentApp &&
        !parsed.isHighConfidence &&
        parsed.accountMask == null &&
        parsed.referenceNumber == null) {
      const reason = 'No account or reference: looks like a promotion';
      await _logFailed(notification, logId, now, reason);
      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.failed,
        isDuplicate: false,
        failureReason: reason,
      );
    }

    // 3. Persist successful raw audit log
    await database.ingestionLogsDao.insertLog(
      RawIngestionLogsCompanion(
        id: Value(logId),
        sourceChannel: Value(notification.channel),
        senderHeader: Value(_sender(notification)),
        sourcePackage: Value(notification.packageName),
        rawPayload: Value(notification.body),
        receivedAt: Value(notification.receivedAt),
        parseStatus: const Value(ParseStatus.parsed),
        confidenceScore: Value(parsed.confidenceScore),
        createdAt: Value(now),
      ),
    );

    final signedAmount = parsed.isDebit
        ? -parsed.amountMinorUnits
        : parsed.amountMinorUnits;

    // 4. Which account: by its last digits; a guess is flagged for review.
    final resolved = await _resolveAccount(parsed);
    final accountId = resolved.id;

    // 5. Is this the bank's own message for a payment the salary plan
    // already recorded (SIP, rent, the move to the spending account)? Then
    // attach to that entry instead of counting the money twice.
    final planned = await _matchPlanned(
      accountId,
      signedAmount,
      parsed.timestamp,
    );
    if (planned != null) {
      await _sameAs(logId, planned.id);
      await (database.update(
        database.transactions,
      )..where((t) => t.id.equals(planned.id))).write(
        TransactionsCompanion(
          transactionState: const Value(TransactionState.reconciled),
          referenceNumber: Value(_fit(parsed.referenceNumber, 80)),
        ),
      );
      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.parsed,
        isDuplicate: true,
        parsedTransaction: parsed,
        persistedTransactionId: planned.id,
      );
    }

    // 6. Already recorded? (UPI app + bank SMS for one payment, or a spend
    // the user logged by hand before the bank's message arrived.)
    final duplicate = await _findDuplicate(
      parsed,
      accountId,
      signedAmount,
      notification,
    );
    if (duplicate != null) {
      await _sameAs(logId, duplicate.id);
      if (duplicate.referenceNumber == null && parsed.referenceNumber != null) {
        await (database.update(
          database.transactions,
        )..where((t) => t.id.equals(duplicate.id))).write(
          TransactionsCompanion(
            referenceNumber: Value(_fit(parsed.referenceNumber, 80)),
          ),
        );
      }
      // The payment app guessed the account; the bank's message names it.
      // Still waiting for Accept, nothing was applied: just correct it.
      if (resolved.sure &&
          duplicate.physicalAccountId != accountId &&
          duplicate.transactionState == TransactionState.needsReview &&
          !duplicate.isInternalTransfer) {
        await (database.update(database.transactions)
              ..where((t) => t.id.equals(duplicate.id)))
            .write(TransactionsCompanion(physicalAccountId: Value(accountId)));
      }
      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.parsed,
        isDuplicate: true,
        parsedTransaction: parsed,
        persistedTransactionId: duplicate.id,
      );
    }

    // 7. A card bill: the bank's debit and the card's "payment received"
    // are two legs of one transfer. Pair with the other leg if it is
    // already here; the card side is never counted twice.
    if (parsed.suggestedTransactionType ==
        TransactionType.creditCardSettlement) {
      final paired = await _pairCardBill(
        parsed: parsed,
        accountId: accountId,
        signedAmount: signedAmount,
      );
      if (paired != null) {
        await _sameAs(logId, paired);
        return IngestionResult(
          rawLogId: logId,
          status: ParseStatus.parsed,
          isDuplicate: true,
          parsedTransaction: parsed,
          persistedTransactionId: paired,
        );
      }
    }

    final txnId = uuid.v4();

    // Is this the real payment for a plan-only category (rent, family...)?
    // Exact planned amount, out of the salary account, category still unpaid.
    final category = await _matchPlanCategory(accountId, signedAmount);

    // The user's own rules: a category, or "ignore this kind of message".
    final rule = category != null
        ? null
        : await CaptureRules(database).match(
            merchant: parsed.merchant ?? '',
            message: notification.body,
            amountMinorUnits: signedAmount,
          );
    if (rule != null && rule.ignore) {
      await database.ingestionLogsDao.updateParseStatus(
        logId,
        ParseStatus.ignored,
        failureReason: 'Ignored by your rule: ${rule.contains}',
      );
      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.ignored,
        isDuplicate: false,
        parsedTransaction: parsed,
      );
    }

    // By default (set when the app starts) every capture waits on Home for
    // Accept or Ignore, so nothing counts, or counts twice, unseen. Turning
    // "accept automatically" on lets confident, certain ones through.
    // Only from a sender Rivero can verify: an SMS worded like a bank's,
    // from anyone's number, always waits for the user.
    final auto =
        await database.settingsDao.get(SettingKeys.captureAutoAccept) != '0';
    final verified = parser.dltValidator.isVerifiedSender(
      senderHeader: notification.sender,
      packageName: notification.packageName,
    );
    final state =
        auto &&
            verified &&
            category == null &&
            parsed.isHighConfidence &&
            resolved.sure
        ? TransactionState.confirmed
        // A guess about WHICH category is always the user's call to confirm.
        : TransactionState.needsReview;

    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(txnId),
        ingestionLogId: Value(logId),
        physicalAccountId: Value(accountId),
        amountMinorUnits: Value(signedAmount),
        allocationBucketId: Value(category?.id),
        transactionType: Value(
          category != null
              ? TransactionType.planTransfer
              : parsed.suggestedTransactionType,
        ),
        transactionState: Value(state),
        merchant: Value(_fit(parsed.merchant, 120) ?? 'Unknown Merchant'),
        category: Value(
          _fit(category?.name ?? rule?.category ?? parsed.category, 60) ??
              'General Expense',
        ),
        referenceNumber: Value(_fit(parsed.referenceNumber, 80)),
        transactionTimestamp: Value(parsed.timestamp),
        createdAt: Value(now),
      ),
    );

    // Auto-confirmed transactions take effect immediately; others wait for
    // the user's swipe, which goes through LedgerService.confirm.
    // A card bill paid from the bank also lowers what the card owes.
    if (parsed.suggestedTransactionType ==
            TransactionType.creditCardSettlement &&
        parsed.isDebit) {
      await _createCardLeg(parsed, txnId, accountId, state, now);
    }

    if (state == TransactionState.confirmed) {
      final saved = await database.transactionsDao.getTransactionById(txnId);
      if (saved != null) await LedgerService(database).applyEffects(saved);
      // Only the amount moves the balance. A "Bal Rs..." in the message is
      // never taken: messages do not come for every payment and every bank
      // words them differently, so the balance the user entered (plus what
      // was recorded since) is the truth.
      await ReconciliationService(database: database).reconcileAll();
    }

    return IngestionResult(
      rawLogId: logId,
      status: ParseStatus.parsed,
      isDuplicate: false,
      parsedTransaction: parsed,
      persistedTransactionId: txnId,
    );
  }

  Future<IngestionResult> _handleNotice(
    RawNotification notification,
    MessageIntent intent,
    String logId,
    DateTime now,
  ) async {
    final isOtp = intent == MessageIntent.otp;
    final mandateRelated =
        intent == MessageIntent.preDebit ||
        intent == MessageIntent.mandateCreated ||
        intent == MessageIntent.mandateCancelled;

    await database.ingestionLogsDao.insertLog(
      RawIngestionLogsCompanion(
        id: Value(logId),
        sourceChannel: Value(notification.channel),
        senderHeader: Value(_sender(notification)),
        sourcePackage: Value(notification.packageName),
        // Never persist one-time passwords.
        rawPayload: Value(
          isOtp ? '[OTP message not stored]' : notification.body,
        ),
        receivedAt: Value(notification.receivedAt),
        parseStatus: Value(
          mandateRelated
              ? ParseStatus.parsed
              // A failed autopay is shown to the user (money may be short).
              : intent == MessageIntent.mandateFailed
              ? ParseStatus.failed
              : ParseStatus.ignored,
        ),
        confidenceScore: const Value(1),
        failureReason: Value(
          mandateRelated
              ? null
              : intent == MessageIntent.mandateFailed
              ? IngestionLogsDao.autopayFailed
              : 'Not a transaction: ${intent.name}',
        ),
        createdAt: Value(now),
      ),
    );

    if (mandateRelated) {
      await MandateTracker(database).apply(
        parser.parseNotice(notification.body, intent),
        now: notification.receivedAt,
      );
    }

    return IngestionResult(
      rawLogId: logId,
      status: mandateRelated
          ? ParseStatus.parsed
          : intent == MessageIntent.mandateFailed
          ? ParseStatus.failed
          : ParseStatus.ignored,
      isDuplicate: false,
    );
  }

  /// The oldest still-unmatched plan entry on [accountId] with exactly this
  /// signed amount, if any. Only from the last pay cycle or so: an old move
  /// whose bank message never came must not swallow a real payment of the
  /// same amount months later.
  Future<LedgerTransaction?> _matchPlanned(
    String accountId,
    int signedAmount,
    DateTime at,
  ) async {
    final candidates =
        await (database.select(database.transactions)
              ..where(
                (t) =>
                    t.id.like('plan-%') &
                    t.physicalAccountId.equals(accountId) &
                    t.amountMinorUnits.equals(signedAmount) &
                    t.transactionState.equals(TransactionState.confirmed.name) &
                    t.referenceNumber.isNull() &
                    t.transactionTimestamp.isBiggerOrEqualValue(
                      at.subtract(const Duration(days: 35)),
                    ),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
            .get();
    return candidates.firstOrNull;
  }

  /// A plan-only category whose planned amount equals this debit from the
  /// salary account and that has not been paid yet this cycle, if exactly
  /// one such category exists (ambiguous amounts are left alone).
  Future<AllocationBucket?> _matchPlanCategory(
    String accountId,
    int signedAmount,
  ) async {
    if (signedAmount >= 0) return null;
    final accounts = await database.accountsDao.getAllActivePhysicalAccounts();
    final salary = PlanTransferService.salaryAccountOf(
      accounts,
      await database.settingsDao.get(SettingKeys.salaryAccount),
    );
    if (salary == null || salary.id != accountId) return null;
    final hits = (await database.accountsDao.getAllBuckets()).where(
      (b) =>
          b.role != AccountRole.expense &&
          (b.linkedPhysicalAccountId == null ||
              b.linkedPhysicalAccountId == salary.id) &&
          b.allocatedMinorUnits == -signedAmount &&
          b.spentMinorUnits == 0,
    );
    return hits.length == 1 ? hits.single : null;
  }

  Future<void> _logFailed(
    RawNotification notification,
    String logId,
    DateTime now,
    String reason,
  ) => database.ingestionLogsDao.insertLog(
    RawIngestionLogsCompanion(
      id: Value(logId),
      sourceChannel: Value(notification.channel),
      senderHeader: Value(_sender(notification)),
      sourcePackage: Value(notification.packageName),
      rawPayload: Value(notification.body),
      receivedAt: Value(notification.receivedAt),
      parseStatus: const Value(ParseStatus.failed),
      confidenceScore: const Value(0),
      failureReason: Value(reason),
      createdAt: Value(now),
    ),
  );

  /// Who sent it, as stored on its log: the SMS sender or the app's title
  /// (or package). Never empty and never longer than the column allows,
  /// or saving it would fail and the whole notification would be lost.
  static String? _sender(RawNotification n) =>
      _fit(n.sender, 50) ?? _fit(n.packageName, 50);

  /// [s] trimmed to at most [max] characters; null when empty.
  static String? _fit(String? s, int max) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length <= max ? t : t.substring(0, max);
  }

  /// Real last digits. All zeros is the placeholder older versions saved
  /// when the digits were left empty: not digits Rivero knows.
  static bool _knownMask(String mask) =>
      RegExp(r'^\d{3,6}$').hasMatch(mask.trim()) &&
      !RegExp(r'^0+$').hasMatch(mask.trim());

  /// Whether the money in this message moved on a card (not a bank account).
  static bool _isCardMessage(ParsedTransaction p) {
    final type = p.suggestedTransactionType;
    if (type == TransactionType.creditCardPurchase) return true;
    // "Paid towards your credit card" from the bank is a bank debit.
    if (type == TransactionType.creditCardSettlement) return !p.isDebit;
    return p.accountType == 'Card';
  }

  /// The account this message is about. `sure` is false when Rivero had to
  /// guess between several accounts: such captures wait for review.
  Future<({String id, bool sure})> _resolveAccount(
    ParsedTransaction parsed,
  ) async {
    final all = await database.accountsDao.getAllActivePhysicalAccounts();
    final mask = parsed.accountMask;

    // 1. Exact last digits.
    if (mask != null) {
      final hit = all
          .where((a) => _knownMask(mask) && a.accountMask.trim() == mask)
          .firstOrNull;
      if (hit != null) return (id: hit.id, sure: true);
    }

    // 2. Right kind of account: cards for card messages, banks otherwise.
    final card = _isCardMessage(parsed);
    final kind = all.where((a) => a.isLiability == card).toList();
    if (kind.isEmpty) return (id: await _createAccount(parsed), sure: true);

    // Accounts whose digits Rivero does not know yet could be this one;
    // an account with different known digits cannot.
    final open = mask == null
        ? kind
        : kind.where((a) => !_knownMask(a.accountMask)).toList();
    if (open.length == 1) {
      final only = open.single;
      // Only one possible account: learn its digits for next time.
      if (mask != null && kind.length == 1) {
        await (database.update(database.physicalAccounts)
              ..where((a) => a.id.equals(only.id)))
            .write(PhysicalAccountsCompanion(accountMask: Value(mask)));
      }
      return (id: only.id, sure: kind.length == 1 || mask == null);
    }
    if (open.isEmpty && mask != null) {
      // Digits nobody has: a new account the user has not added yet.
      return (id: await _createAccount(parsed), sure: false);
    }

    // Several candidates: bank money most likely moved in the salary
    // account; either way the user confirms.
    final pool = open.isEmpty ? kind : open;
    final salary = card
        ? null
        : PlanTransferService.salaryAccountOf(
            pool,
            await database.settingsDao.get(SettingKeys.salaryAccount),
          );
    return (id: (salary ?? pool.first).id, sure: false);
  }

  Future<String> _createAccount(ParsedTransaction parsed) async {
    final newId = uuid.v4();
    final now = DateTime.now();
    final card = _isCardMessage(parsed);
    await database.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: Value(newId),
        name: Value(_fit(_accountName(parsed, card: card), 100)!),
        institution: Value(_fit(parsed.financialInstitution, 50) ?? 'Bank'),
        accountMask: Value(_fit(parsed.accountMask, 20) ?? '••••'),
        isLiability: Value(card),
        accountType: Value(
          card ? StandardAccountTypes.creditCard : StandardAccountTypes.savings,
        ),
        balanceMinorUnits: const Value(0),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return newId;
  }

  /// "HDFC Bank Account (**4321)"; a sender already called "... Credit
  /// Card" is not given a second "Card".
  static String _accountName(ParsedTransaction parsed, {required bool card}) {
    final bank = parsed.financialInstitution ?? 'Bank';
    final kind = card ? 'Card' : 'Account';
    final named = bank.toLowerCase().endsWith(kind.toLowerCase());
    return '${named ? bank : '$bank $kind'}'
        '${parsed.accountMask != null ? " (**${parsed.accountMask})" : ""}';
  }

  /// The entry this message duplicates, if any.
  Future<LedgerTransaction?> _findDuplicate(
    ParsedTransaction parsed,
    String accountId,
    int signedAmount,
    RawNotification notification,
  ) async {
    // Two notifications for one payment arrive within minutes.
    final near = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
    );
    final candidates = <LedgerTransaction>[];
    for (final t in near) {
      if (t.id.startsWith('plan-')) continue;
      if (await _anotherPaymentFromSameSource(t, parsed, notification)) {
        continue;
      }
      candidates.add(t);
    }
    final match = deduplicator.evaluate(
      candidate: parsed,
      existingTransactions: candidates,
    );
    if (match.isDuplicate) return match.matchedTransaction;

    final echo = await _appAndBankPair(parsed, signedAmount, notification);
    if (echo != null) return echo;

    // A spend logged by hand can be hours away from the bank's message:
    // same account, same amount, within 6 hours, not yet matched to a
    // bank message (no reference).
    final manual = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
      window: const Duration(hours: 6),
    );
    final typedIn = manual
        .where(
          (t) =>
              t.id.startsWith('txn-manual-') &&
              t.physicalAccountId == accountId &&
              t.referenceNumber == null,
        )
        .firstOrNull;
    if (typedIn != null) return typedIn;

    // A plan category marked "Paying now" (rent, family): the bank's
    // message for it can arrive days later, and is that same payment.
    final planPaid = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
      window: const Duration(days: 7),
    );
    return planPaid
        .where(
          (t) =>
              t.id.startsWith('txn-manual-') &&
              t.transactionType == TransactionType.planTransfer &&
              t.allocationBucketId != null &&
              t.physicalAccountId == accountId &&
              t.referenceNumber == null,
        )
        .firstOrNull;
  }

  /// One payment is announced once per app: the payment app, then the
  /// bank. So a second message from the SAME app (and for SMS the same
  /// sender) naming a different payee is another payment, even for the
  /// same amount in the same minute. Same reference = same payment.
  // ponytail: same payee, same amount, same app within a minute still
  // counts once (apps do repost a notification); the user logs the second.
  Future<bool> _anotherPaymentFromSameSource(
    LedgerTransaction existing,
    ParsedTransaction parsed,
    RawNotification n,
  ) async {
    final logId = existing.ingestionLogId;
    final pkg = n.packageName;
    if (logId == null || pkg == null) return false;
    if (parsed.referenceNumber != null &&
        parsed.referenceNumber == existing.referenceNumber) {
      return false;
    }
    final log = await (database.select(
      database.rawIngestionLogs,
    )..where((l) => l.id.equals(logId))).getSingleOrNull();
    if (log == null || log.sourcePackage != pkg) return false;
    final paymentApp = parser.dltValidator.isFinancialSender(packageName: pkg);
    if (!paymentApp && log.senderHeader != (n.sender ?? pkg)) return false;
    final a = existing.merchant.toLowerCase().trim();
    final b = (parsed.merchant ?? '').toLowerCase().trim();
    return b.isNotEmpty && a != b && !a.contains(b) && !b.contains(a);
  }

  /// The payment app's notification and the bank's message for one payment:
  /// the bank's can come many minutes later and name the payee differently
  /// ("Cafe Coffee Day" vs "ccdpayments@icici"). Within 30 minutes, same
  /// amount and direction, one side from a payment app with no reference
  /// and the other a bank message with one, they are one payment. Each side
  /// pairs once, so two real payments of one amount stay two.
  Future<LedgerTransaction?> _appAndBankPair(
    ParsedTransaction parsed,
    int signedAmount,
    RawNotification n,
  ) async {
    bool fromApp(String? pkg) =>
        pkg != null && parser.dltValidator.isFinancialSender(packageName: pkg);
    final incomingFromApp =
        fromApp(n.packageName) && parsed.referenceNumber == null;
    final incomingFromBank =
        !fromApp(n.packageName) && parsed.referenceNumber != null;
    if (!incomingFromApp && !incomingFromBank) return null;

    final near = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
      window: const Duration(minutes: 30),
    );
    LedgerTransaction? best;
    for (final t in near) {
      final logId = t.ingestionLogId;
      if (logId == null || t.id.startsWith('plan-') || t.isInternalTransfer) {
        continue;
      }
      final log = await (database.select(
        database.rawIngestionLogs,
      )..where((l) => l.id.equals(logId))).getSingleOrNull();
      if (log == null) continue;
      final ok = incomingFromBank
          // An app notification not yet joined by its bank message.
          ? fromApp(log.sourcePackage) && t.referenceNumber == null
          // A bank message not yet joined by an app notification.
          : !fromApp(log.sourcePackage) &&
                t.referenceNumber != null &&
                !await _joinedByApp(t.id, fromApp);
      if (!ok) continue;
      final gap = t.transactionTimestamp.difference(parsed.timestamp).abs();
      if (best == null ||
          gap < best.transactionTimestamp.difference(parsed.timestamp).abs()) {
        best = t;
      }
    }
    return best;
  }

  /// Whether a payment app's notification was already matched to [id].
  Future<bool> _joinedByApp(String id, bool Function(String?) fromApp) async {
    final logs = await (database.select(
      database.rawIngestionLogs,
    )..where((l) => l.matchedTransactionId.equals(id))).get();
    return logs.any((l) => fromApp(l.sourcePackage));
  }

  /// This message repeats entry [transactionId]: remembered, so a choice
  /// made on its notification and the balance it reports reach that entry.
  Future<void> _sameAs(String logId, String transactionId) =>
      (database.update(
        database.rawIngestionLogs,
      )..where((l) => l.id.equals(logId))).write(
        RawIngestionLogsCompanion(matchedTransactionId: Value(transactionId)),
      );

  /// The card a bill payment went to: the card whose digits the message
  /// mentions, else the only card.
  Future<PhysicalAccount?> _billedCard(String text, String? exceptId) async {
    final cards = (await database.accountsDao.getAllActivePhysicalAccounts())
        .where((a) => a.isLiability && a.id != exceptId)
        .toList();
    final named = cards
        .where(
          (c) =>
              _knownMask(c.accountMask) && text.contains(c.accountMask.trim()),
        )
        .toList();
    if (named.length == 1) return named.single;
    return cards.length == 1 ? cards.single : null;
  }

  /// If the other leg of this card-bill payment is already recorded, links
  /// to it and returns its id (this message adds nothing new).
  Future<String?> _pairCardBill({
    required ParsedTransaction parsed,
    required String accountId,
    required int signedAmount,
  }) async {
    final since = parsed.timestamp.subtract(const Duration(days: 3));
    final until = parsed.timestamp.add(const Duration(days: 3));
    final all =
        await (database.select(database.transactions)..where(
              (t) => t.transactionTimestamp.isBetweenValues(since, until),
            ))
            .get();
    if (parsed.isDebit) {
      // Bank message after the card's own "payment received".
      final card = await _billedCard(parsed.rawPayload, accountId);
      if (card == null) return null;
      final leg = all
          .where(
            (t) =>
                t.physicalAccountId == card.id &&
                t.amountMinorUnits == -signedAmount &&
                t.linkedTransactionId == null &&
                // An ignored card message is no payment to pair with.
                t.transactionState != TransactionState.ignored &&
                t.transactionTimestamp.isAfter(since) &&
                t.transactionTimestamp.isBefore(until),
          )
          .firstOrNull;
      if (leg == null) return null;
      // Record the bank side, linked to the card side, as a transfer. It
      // follows the card side: still waiting for Accept there, it waits
      // too, and the two are accepted or ignored together.
      final legApplied =
          leg.transactionState == TransactionState.confirmed ||
          leg.transactionState == TransactionState.reconciled;
      final id = uuid.v4();
      await database.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value(id),
          physicalAccountId: Value(accountId),
          amountMinorUnits: Value(signedAmount),
          transactionType: const Value(TransactionType.creditCardSettlement),
          transactionState: Value(
            legApplied
                ? TransactionState.confirmed
                : TransactionState.needsReview,
          ),
          merchant: Value('Card bill: ${card.name}'),
          category: const Value('Card bill'),
          referenceNumber: Value(_fit(parsed.referenceNumber, 80)),
          transactionTimestamp: Value(parsed.timestamp),
          createdAt: Value(DateTime.now()),
          isInternalTransfer: const Value(true),
          linkedTransactionId: Value(leg.id),
        ),
      );
      if (legApplied) {
        final saved = await database.transactionsDao.getTransactionById(id);
        if (saved != null) await LedgerService(database).applyEffects(saved);
      }
      await database.transactionsDao.linkTransactionLegs(id, leg.id);
      return id;
    }
    // Card's "payment received" after the bank's message: the card leg
    // Rivero created then is this payment.
    final leg = all
        .where(
          (t) =>
              t.id.startsWith('cc-') &&
              t.physicalAccountId == accountId &&
              t.amountMinorUnits == signedAmount &&
              t.transactionTimestamp.isAfter(since) &&
              t.transactionTimestamp.isBefore(until),
        )
        .firstOrNull;
    return leg?.id;
  }

  /// The card side of a bill paid from the bank: what the card owes drops.
  Future<void> _createCardLeg(
    ParsedTransaction parsed,
    String bankTxnId,
    String bankAccountId,
    TransactionState state,
    DateTime now,
  ) async {
    final card = await _billedCard(parsed.rawPayload, bankAccountId);
    if (card == null) return;
    final id = 'cc-$bankTxnId';
    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(id),
        physicalAccountId: Value(card.id),
        amountMinorUnits: Value(parsed.amountMinorUnits),
        transactionType: const Value(TransactionType.creditCardSettlement),
        transactionState: Value(state),
        merchant: const Value('Card bill paid'),
        category: const Value('Card bill'),
        transactionTimestamp: Value(parsed.timestamp),
        createdAt: Value(now),
        isInternalTransfer: const Value(true),
        linkedTransactionId: Value(bankTxnId),
      ),
    );
    await (database.update(
      database.transactions,
    )..where((t) => t.id.equals(bankTxnId))).write(
      TransactionsCompanion(
        isInternalTransfer: const Value(true),
        linkedTransactionId: Value(id),
      ),
    );
    if (state == TransactionState.confirmed) {
      final saved = await database.transactionsDao.getTransactionById(id);
      if (saved != null) await LedgerService(database).applyEffects(saved);
    }
  }
}
