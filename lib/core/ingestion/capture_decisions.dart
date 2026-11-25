import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';

/// Choices made in the popup of a capture notification (Add with a category
/// and note, or Ignore), applied once that capture has been processed.
/// Keyed by the capture id, which is also the capture's ingestion log id.
class CaptureDecisions {
  const CaptureDecisions(this.db);

  final RiveroDatabase db;

  /// The entry Rivero made from capture [captureId], if any.
  Future<LedgerTransaction?> entryFor(String captureId) async {
    final own =
        await (db.select(db.transactions)
              ..where((t) => t.ingestionLogId.equals(captureId))
              ..limit(1))
            .getSingleOrNull();
    return own ?? await _repeated(captureId);
  }

  /// A message Rivero could not read (it waits on Home under "bank
  /// messages to check"): Ignore dismisses it; Add keeps the category and
  /// note for when it is added from there. False if it is not such a one.
  Future<bool> _unreadable(String captureId, Map<String, dynamic> d) async {
    final log = await (db.select(
      db.rawIngestionLogs,
    )..where((l) => l.id.equals(captureId))).getSingleOrNull();
    if (log == null ||
        log.parseStatus != ParseStatus.failed ||
        log.failureReason == IngestionLogsDao.autopayFailed) {
      return false;
    }
    if (d['action'] == 'ignore') {
      await db.ingestionLogsDao.updateParseStatus(
        captureId,
        ParseStatus.ignored,
        failureReason: 'Dismissed',
      );
      return true;
    }
    final all = await unreadableChoices(db);
    all[captureId] = {
      'category': d['category'],
      'note': d['note'],
      'account': d['account'],
    };
    await db.settingsDao.set(SettingKeys.unreadableChoices, jsonEncode(all));
    return true;
  }

  /// Choices kept by [_unreadable], by log id.
  static Future<Map<String, dynamic>> unreadableChoices(
    RiveroDatabase db,
  ) async {
    final raw = await db.settingsDao.get(SettingKeys.unreadableChoices);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on FormatException {
      return {};
    }
  }

  /// The entry a second notification for the same payment was matched to.
  Future<LedgerTransaction?> _repeated(String captureId) async {
    final log = await (db.select(
      db.rawIngestionLogs,
    )..where((l) => l.id.equals(captureId))).getSingleOrNull();
    final id = log?.matchedTransactionId;
    return id == null ? null : await db.transactionsDao.getTransactionById(id);
  }

  /// Applies [decisions] ({captureId: {action, category, note, account}}). Returns how
  /// many were applied; captures that made no entry (a duplicate, a
  /// promotion) are skipped.
  Future<int> apply(Map<String, dynamic> decisions) async {
    final ledger = LedgerService(db);
    var applied = 0;
    // Choices whose notification was not processed yet (it can arrive a
    // moment later, or the app was frozen in between) wait for it here.
    final waiting = await _waiting();
    final all = {...waiting, ...decisions};
    final stillWaiting = <String, dynamic>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in all.entries) {
      final d = (e.value as Map).cast<String, dynamic>();
      final t = await entryFor(e.key);
      if (t == null) {
        if (await _unreadable(e.key, d)) {
          applied++;
        } else if (!await _logged(e.key)) {
          final since = d['since'] as int? ?? now;
          if (now - since < const Duration(days: 3).inMilliseconds) {
            stillWaiting[e.key] = {...d, 'since': since};
          }
        }
        continue;
      }
      // A choice made on the second notification of one payment (or on a
      // payment already logged by hand): it never ignores or removes what
      // is already recorded. An Add still files it: the category and
      // description picked are applied to that entry.
      if (t.ingestionLogId != e.key &&
          (d['action'] == 'ignore' ||
              t.transactionState != TransactionState.needsReview)) {
        if (d['action'] != 'ignore' &&
            t.transactionState != TransactionState.ignored) {
          await _label(t, d);
          await _move(ledger, t, d);
          applied++;
        }
        continue;
      }
      if (d['action'] == 'ignore') {
        final counted =
            t.transactionState == TransactionState.confirmed ||
            t.transactionState == TransactionState.reconciled;
        // Already counted (automatic acceptance on): undo it.
        counted
            ? await ledger.removeWithPlanPartner(t.id)
            : await ledger.ignore(t.id);
      } else {
        await _label(t, d);
        await _move(ledger, t, d);
        await ledger.confirm(t.id);
        await ReconciliationService(database: db).reconcileAll();
      }
      applied++;
    }
    if (stillWaiting.isNotEmpty || waiting.isNotEmpty) {
      await db.settingsDao.set(
        SettingKeys.waitingDecisions,
        jsonEncode(stillWaiting),
      );
    }
    return applied;
  }

  /// Writes the category and description picked on a pop-up to [t].
  Future<void> _label(LedgerTransaction t, Map<String, dynamic> d) async {
    final category = d['category'] as String?;
    final note = (d['note'] as String?)?.trim();
    if ((category == null || category.isEmpty) &&
        (note == null || note.isEmpty)) {
      return;
    }
    await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(
      TransactionsCompanion(
        category: category == null || category.isEmpty
            ? const Value.absent()
            : Value(category),
        userNotes: note == null || note.isEmpty
            ? const Value.absent()
            : Value(note),
      ),
    );
  }

  /// Moves [t] to the account picked on the pop-up, if one was picked and
  /// it still exists. A transfer stays where it is.
  Future<void> _move(
    LedgerService ledger,
    LedgerTransaction t,
    Map<String, dynamic> d,
  ) async {
    final account = d['account'] as String?;
    if (account == null || account.isEmpty) return;
    // A transfer: both sides are already matched to their accounts.
    if (t.isInternalTransfer || t.linkedTransactionId != null) return;
    await ledger.changeAccount(t.id, account);
  }

  Future<Map<String, dynamic>> _waiting() async {
    final raw = await db.settingsDao.get(SettingKeys.waitingDecisions);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on FormatException {
      return {};
    }
  }

  /// Whether Rivero has processed notification [captureId] at all.
  Future<bool> _logged(String captureId) async =>
      await (db.select(
        db.rawIngestionLogs,
      )..where((l) => l.id.equals(captureId))).getSingleOrNull() !=
      null;
}
