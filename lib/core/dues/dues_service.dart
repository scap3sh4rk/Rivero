import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

/// A user-facing validation problem with a message to show.
class DueValidationException implements Exception {
  const DueValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Money owed to the user: split bills and money lent.
///
/// Rules (no double counting):
/// * A split bill's other shares stop counting as *your* spending at once,
///   but the budget only gets the money back when it actually arrives.
/// * Lending is not spending: the account balance drops, the budget doesn't.
/// * A repayment is tagged "Paid back", never counted as income.
/// * Writing off money you lent turns it into spending (it is gone).
class DuesService {
  DuesService(this.db);

  final RiveroDatabase db;

  int outstandingOf(Due d) => d.amountMinorUnits - d.receivedMinorUnits;

  /// A date entered by the user must not be in the future.
  static void _checkDate(DateTime? on) {
    if (on != null && on.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw const DueValidationException('That date is in the future');
    }
  }

  /// Splits [total] equally between [people] (including you). Others get
  /// whole paise; any remainder stays with you. Returns the others' shares.
  static List<int> equalShares(int total, int people) {
    if (people < 2 || total <= 0) return const [];
    final each = total ~/ people;
    return List<int>.filled(people - 1, each);
  }

  Future<void> splitExpense({
    required String transactionId,
    required Map<String, int> shares,
    String? note,
    String? creditAccountId,
  }) async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null || t.amountMinorUnits >= 0) {
      throw const DueValidationException(
        'Only a payment you made can be split',
      );
    }
    final clean = <String, int>{};
    for (final e in shares.entries) {
      final name = e.key.trim();
      if (name.isEmpty) {
        throw const DueValidationException('Add a name for each person');
      }
      if (e.value <= 0) throw DueValidationException('$name needs an amount');
      clean[name] = (clean[name] ?? 0) + e.value;
    }
    if (clean.isEmpty) {
      throw const DueValidationException('Add at least one person');
    }
    final total = clean.values.fold<int>(0, (a, b) => a + b);
    if (total > -t.amountMinorUnits) {
      throw const DueValidationException('Their shares are more than the bill');
    }
    final now = DateTime.now();
    for (final e in clean.entries) {
      await db
          .into(db.dues)
          .insert(
            DuesCompanion.insert(
              id: 'due-${now.microsecondsSinceEpoch}-${e.key.hashCode.abs()}',
              person: e.key,
              amountMinorUnits: e.value,
              kind: DueKind.split,
              status: DueStatus.open,
              note: Value(note ?? t.merchant),
              sourceTransactionId: Value(t.id),
              creditAccountId: Value(creditAccountId),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  /// Records money lent to [person]. With [accountId], the outflow is logged
  /// on that account as lending (not spending); without, it was cash.
  Future<void> lend({
    required String person,
    required int amountMinorUnits,
    String? accountId,
    String? note,
    DateTime? on,
    String? attachmentPath,
  }) async {
    final name = person.trim();
    _checkDate(on);
    if (name.isEmpty) {
      throw const DueValidationException('Who did you lend to?');
    }
    if (amountMinorUnits <= 0) {
      throw const DueValidationException('Enter an amount');
    }
    String? sourceId;
    if (accountId != null) {
      sourceId = await LedgerService(db).recordManual(
        accountId: accountId,
        amountMinorUnits: -amountMinorUnits,
        type: TransactionType.lending,
        merchant: 'Lent to $name',
        category: 'Lent',
        note: note,
        at: on,
        attachmentPath: attachmentPath,
      );
    }
    final now = DateTime.now();
    await db
        .into(db.dues)
        .insert(
          DuesCompanion.insert(
            id: 'due-${now.microsecondsSinceEpoch}',
            person: name,
            amountMinorUnits: amountMinorUnits,
            kind: DueKind.lent,
            status: DueStatus.open,
            note: Value(note),
            attachmentPath: Value(attachmentPath),
            sourceTransactionId: Value(sourceId),
            // The day it really happened (it may be logged later).
            createdAt: on ?? now,
            updatedAt: now,
          ),
        );
  }

  /// Records money you borrowed from [person]. With [accountId] the money
  /// arrived in that account (logged as borrowing: not income); without, it
  /// was cash. [dueDate] is when you promised to pay it back.
  Future<void> borrow({
    required String person,
    required int amountMinorUnits,
    String? accountId,
    DateTime? dueDate,
    String? note,
    DateTime? on,
    String? attachmentPath,
  }) => db.transaction(() async {
    final name = person.trim();
    _checkDate(on);
    if (name.isEmpty) {
      throw const DueValidationException('Who did you borrow from?');
    }
    if (amountMinorUnits <= 0) {
      throw const DueValidationException('Enter an amount');
    }
    String? sourceId;
    if (accountId != null) {
      sourceId = await LedgerService(db).recordManual(
        accountId: accountId,
        amountMinorUnits: amountMinorUnits,
        type: TransactionType.borrowing,
        merchant: 'Borrowed from $name',
        category: 'Borrowed',
        note: note,
        at: on,
        attachmentPath: attachmentPath,
      );
    }
    final now = DateTime.now();
    await db
        .into(db.dues)
        .insert(
          DuesCompanion.insert(
            id: 'due-${now.microsecondsSinceEpoch}',
            person: name,
            amountMinorUnits: amountMinorUnits,
            kind: DueKind.borrowed,
            status: DueStatus.open,
            note: Value(note),
            dueDate: Value(dueDate),
            attachmentPath: Value(attachmentPath),
            sourceTransactionId: Value(sourceId),
            createdAt: on ?? now,
            updatedAt: now,
          ),
        );
  });

  /// Records [amountMinorUnits] paid back to someone you owe. With
  /// [accountId] it leaves that account (logged as a repayment: not
  /// spending, it was spent when borrowed); without, you paid in cash.
  Future<void> repay(String dueId, int amountMinorUnits, {String? accountId}) =>
      db.transaction(() async {
        final d = await _get(dueId);
        if (d.kind != DueKind.borrowed) {
          throw const DueValidationException('This is owed to you');
        }
        if (d.status != DueStatus.open) {
          throw const DueValidationException('This is already closed');
        }
        if (amountMinorUnits <= 0 || amountMinorUnits > outstandingOf(d)) {
          throw const DueValidationException(
            'Amount is more than what you owe',
          );
        }
        if (accountId != null) {
          await LedgerService(db).recordManual(
            accountId: accountId,
            amountMinorUnits: -amountMinorUnits,
            type: TransactionType.repayment,
            merchant: 'Paid back ${d.person}',
            category: 'Paid back',
          );
        }
        final paid = d.receivedMinorUnits + amountMinorUnits;
        await (db.update(db.dues)..where((x) => x.id.equals(dueId))).write(
          DuesCompanion(
            receivedMinorUnits: Value(paid),
            status: Value(
              paid >= d.amountMinorUnits ? DueStatus.settled : DueStatus.open,
            ),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });

  /// Records [amountMinorUnits] paid back. With [creditTransactionId] the
  /// matching bank credit is tagged "Paid back" (not income); with
  /// [accountId] the money is credited to that account as "Paid back"; with
  /// neither, it was received in cash. Split money goes back into the budget
  /// it came from.
  Future<void> receive(
    String dueId,
    int amountMinorUnits, {
    String? creditTransactionId,
    String? accountId,
  }) async {
    final d = await _get(dueId);
    if (d.kind == DueKind.borrowed) {
      throw const DueValidationException('You owe this: use Paid back');
    }
    if (d.status != DueStatus.open) {
      throw const DueValidationException('This is already closed');
    }
    final outstanding = outstandingOf(d);
    if (amountMinorUnits <= 0 || amountMinorUnits > outstanding) {
      throw const DueValidationException('Amount is more than what is owed');
    }
    await db.transaction(() async {
      if (creditTransactionId == null && accountId != null) {
        await LedgerService(db).recordManual(
          accountId: accountId,
          amountMinorUnits: amountMinorUnits,
          type: TransactionType.reimbursement,
          merchant: 'Paid back by ${d.person}',
          category: 'Paid back',
        );
      }
      if (creditTransactionId != null) {
        await db.transactionsDao.updateTransactionType(
          creditTransactionId,
          TransactionType.reimbursement,
        );
        await db.transactionsDao.updateTransactionCategory(
          creditTransactionId,
          category: 'Paid back',
        );
      }
      if (d.kind == DueKind.split) {
        final bucket = await _bucketFor(d.sourceTransactionId);
        if (bucket != null) {
          await db.accountsDao.recordBucketSpend(bucket, -amountMinorUnits);
        }
      }
      final received = d.receivedMinorUnits + amountMinorUnits;
      await (db.update(db.dues)..where((x) => x.id.equals(dueId))).write(
        DuesCompanion(
          receivedMinorUnits: Value(received),
          status: Value(
            received >= d.amountMinorUnits ? DueStatus.settled : DueStatus.open,
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Gives up on what is still owed. For money lent, the unpaid part becomes
  /// spending; for a split, you simply bore that share.
  Future<void> writeOff(String dueId) async {
    final d = await _get(dueId);
    if (d.status != DueStatus.open) return;
    final outstanding = outstandingOf(d);
    if (d.kind == DueKind.lent && outstanding > 0) {
      final bucket = await _bucketFor(null);
      if (bucket != null) {
        await db.accountsDao.recordBucketSpend(bucket, outstanding);
      }
    }
    await (db.update(db.dues)..where((x) => x.id.equals(dueId))).write(
      DuesCompanion(
        status: const Value(DueStatus.writtenOff),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Credits that could be this person paying back: confirmed incoming
  /// money since the due was created, not already tagged, no larger than
  /// what is owed, closest amount first.
  Future<List<LedgerTransaction>> repaymentCandidates(String dueId) async {
    final d = await _get(dueId);
    final outstanding = outstandingOf(d);
    final since = d.createdAt.subtract(const Duration(days: 1));
    final all = await db.transactionsDao.getRecentTransactions(limit: 300);
    final list =
        all.where((t) {
          return t.amountMinorUnits > 0 &&
              t.amountMinorUnits <= outstanding &&
              t.transactionState == TransactionState.confirmed &&
              !t.isInternalTransfer &&
              t.transactionType != TransactionType.reimbursement &&
              t.transactionTimestamp.isAfter(since);
        }).toList()..sort(
          (a, b) => (outstanding - a.amountMinorUnits).compareTo(
            outstanding - b.amountMinorUnits,
          ),
        );
    return list.take(5).toList();
  }

  /// Other people's shares per split transaction (not written off), used to
  /// show your real spending.
  static Map<String, int> othersShareByTransaction(Iterable<Due> dues) {
    final out = <String, int>{};
    for (final d in dues) {
      final src = d.sourceTransactionId;
      if (d.kind != DueKind.split || src == null) continue;
      if (d.status == DueStatus.writtenOff) continue;
      out[src] = (out[src] ?? 0) + d.amountMinorUnits;
    }
    return out;
  }

  /// Whether two typed names are the same person (case and spaces ignored).
  static bool samePerson(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Everyone ever entered, once each, most recent first: the names to
  /// suggest while typing, so one person's entries stay together.
  static List<String> knownPeople(Iterable<Due> dues) {
    final byKey = <String, Due>{};
    for (final d in dues) {
      final k = d.person.trim().toLowerCase();
      final seen = byKey[k];
      if (seen == null || d.createdAt.isAfter(seen.createdAt)) byKey[k] = d;
    }
    return (byKey.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        .map((d) => d.person.trim())
        .toList();
  }

  /// Total still owed TO YOU (split bills and loans) across open dues.
  static int totalOutstanding(Iterable<Due> dues) => dues
      .where((d) => d.status == DueStatus.open && d.kind != DueKind.borrowed)
      .fold(0, (s, d) => s + d.amountMinorUnits - d.receivedMinorUnits);

  /// Total you still owe to people across open borrowed dues.
  static int totalYouOwe(Iterable<Due> dues) => dues
      .where((d) => d.status == DueStatus.open && d.kind == DueKind.borrowed)
      .fold(0, (s, d) => s + d.amountMinorUnits - d.receivedMinorUnits);

  /// What you owe people that is not yours to spend before [until]: debts
  /// due by then, and borrowed money that came into an account with no
  /// pay-back date (it could be asked back any day; a date after [until]
  /// frees it).
  static int youOweDueBy(Iterable<Due> dues, DateTime until) => dues
      .where(
        (d) =>
            d.status == DueStatus.open &&
            d.kind == DueKind.borrowed &&
            (d.dueDate == null
                ? d.sourceTransactionId != null
                : !d.dueDate!.isAfter(until)),
      )
      .fold(0, (s, d) => s + d.amountMinorUnits - d.receivedMinorUnits);

  Future<Due> _get(String id) async {
    final d = await (db.select(
      db.dues,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (d == null) throw const DueValidationException('Not found');
    return d;
  }

  Future<String?> _bucketFor(String? sourceTransactionId) async {
    if (sourceTransactionId != null) {
      final t = await db.transactionsDao.getTransactionById(
        sourceTransactionId,
      );
      if (t?.allocationBucketId != null) return t!.allocationBucketId;
    }
    return (await db.accountsDao.getBucketsByRole(AccountRole.expense))
        .firstOrNull
        ?.id;
  }
}
