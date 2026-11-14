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
          senderHeader: Value(notification.sender ?? notification.packageName),
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
        senderHeader: Value(notification.sender ?? notification.packageName),
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
    final planned = await _matchPlanned(accountId, signedAmount);
    if (planned != null) {
      await (database.update(
        database.transactions,
      )..where((t) => t.id.equals(planned.id))).write(
        TransactionsCompanion(
          transactionState: const Value(TransactionState.reconciled),
          referenceNumber: Value(parsed.referenceNumber),
        ),
      );
      await _adoptReportedBalance(accountId, parsed.balanceMinorUnits);
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
    final duplicate = await _findDuplicate(parsed, accountId, signedAmount);
    if (duplicate != null) {
      if (duplicate.referenceNumber == null && parsed.referenceNumber != null) {
        await (database.update(
          database.transactions,
        )..where((t) => t.id.equals(duplicate.id))).write(
          TransactionsCompanion(referenceNumber: Value(parsed.referenceNumber)),
        );
      }
      final applied =
          duplicate.transactionState == TransactionState.confirmed ||
          duplicate.transactionState == TransactionState.reconciled;
      if (applied && duplicate.physicalAccountId == accountId) {
        await _adoptReportedBalance(accountId, parsed.balanceMinorUnits);
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
        await _adoptReportedBalance(accountId, parsed.balanceMinorUnits);
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

    final state = category == null && parsed.isHighConfidence && resolved.sure
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
        merchant: Value(parsed.merchant ?? 'Unknown Merchant'),
        category: Value(category?.name ?? parsed.category ?? 'General Expense'),
        referenceNumber: Value(parsed.referenceNumber),
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
      // The bank's own "available balance" is the source of truth for the
      // account; adopting it self-corrects any drift.
      await _adoptReportedBalance(accountId, parsed.balanceMinorUnits);
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
        senderHeader: Value(notification.sender ?? notification.packageName),
        // Never persist one-time passwords.
        rawPayload: Value(
          isOtp ? '[OTP message not stored]' : notification.body,
        ),
        receivedAt: Value(notification.receivedAt),
        parseStatus: Value(
          mandateRelated ? ParseStatus.parsed : ParseStatus.ignored,
        ),
        confidenceScore: const Value(1),
        failureReason: Value(
          mandateRelated ? null : 'Not a transaction: ${intent.name}',
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
      status: mandateRelated ? ParseStatus.parsed : ParseStatus.ignored,
      isDuplicate: false,
    );
  }

  /// The oldest still-unmatched plan entry on [accountId] with exactly this
  /// signed amount, if any.
  Future<LedgerTransaction?> _matchPlanned(
    String accountId,
    int signedAmount,
  ) async {
    final candidates =
        await (database.select(database.transactions)
              ..where(
                (t) =>
                    t.id.like('plan-%') &
                    t.physicalAccountId.equals(accountId) &
                    t.amountMinorUnits.equals(signedAmount) &
                    t.transactionState.equals(TransactionState.confirmed.name) &
                    t.referenceNumber.isNull(),
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

  /// The bank's "available balance" is the truth for a bank account.
  Future<void> _adoptReportedBalance(String accountId, int? reported) async {
    if (reported == null) return;
    final acc = await database.accountsDao.getPhysicalAccountById(accountId);
    if (acc != null && !acc.isLiability) {
      await database.accountsDao.updateAccountBalance(accountId, reported);
    }
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
      senderHeader: Value(notification.sender ?? notification.packageName),
      rawPayload: Value(notification.body),
      receivedAt: Value(notification.receivedAt),
      parseStatus: const Value(ParseStatus.failed),
      confidenceScore: const Value(0),
      failureReason: Value(reason),
      createdAt: Value(now),
    ),
  );

  static bool _knownMask(String mask) =>
      RegExp(r'^\d{3,6}$').hasMatch(mask.trim());

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
      final hit = all.where((a) => a.accountMask.trim() == mask).firstOrNull;
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
        name: Value(
          '${parsed.financialInstitution ?? "Bank"} ${card ? 'Card' : 'Account'}'
          '${parsed.accountMask != null ? " (**${parsed.accountMask})" : ""}',
        ),
        institution: Value(parsed.financialInstitution ?? 'Bank'),
        accountMask: Value(parsed.accountMask ?? '••••'),
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

  /// The entry this message duplicates, if any.
  Future<LedgerTransaction?> _findDuplicate(
    ParsedTransaction parsed,
    String accountId,
    int signedAmount,
  ) async {
    // Two notifications for one payment arrive within minutes.
    final near = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
    );
    final match = deduplicator.evaluate(
      candidate: parsed,
      existingTransactions: near
          .where((t) => !t.id.startsWith('plan-'))
          .toList(),
    );
    if (match.isDuplicate) return match.matchedTransaction;

    // A spend logged by hand can be hours away from the bank's message:
    // same account, same amount, within 6 hours, not yet matched to a
    // bank message (no reference).
    final manual = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
      window: const Duration(hours: 6),
    );
    return manual
        .where(
          (t) =>
              t.id.startsWith('txn-manual-') &&
              t.physicalAccountId == accountId &&
              t.referenceNumber == null,
        )
        .firstOrNull;
  }

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
                t.transactionTimestamp.isAfter(since) &&
                t.transactionTimestamp.isBefore(until),
          )
          .firstOrNull;
      if (leg == null) return null;
      // Record the bank side, linked to the card side, as a transfer.
      final id = uuid.v4();
      await database.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value(id),
          physicalAccountId: Value(accountId),
          amountMinorUnits: Value(signedAmount),
          transactionType: const Value(TransactionType.creditCardSettlement),
          transactionState: const Value(TransactionState.confirmed),
          merchant: Value('Card bill: ${card.name}'),
          category: const Value('Card bill'),
          referenceNumber: Value(parsed.referenceNumber),
          transactionTimestamp: Value(parsed.timestamp),
          createdAt: Value(DateTime.now()),
          isInternalTransfer: const Value(true),
          linkedTransactionId: Value(leg.id),
        ),
      );
      final saved = await database.transactionsDao.getTransactionById(id);
      if (saved != null) await LedgerService(database).applyEffects(saved);
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
