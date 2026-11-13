import 'package:flutter/foundation.dart';

/// What a bank / UPI message is *about*. Only [transaction] moves money.
enum MessageIntent {
  /// A real debit or credit that already happened.
  transaction,

  /// One-time password. Never a transaction, and must not be stored.
  otp,

  /// A "will be debited on a date" reminder, not a debit.
  preDebit,

  /// An autopay / e-mandate was set up.
  mandateCreated,

  /// An autopay / e-mandate was revoked, cancelled or paused.
  mandateCancelled,

  /// An autopay attempt failed (insufficient balance, declined).
  mandateFailed,

  /// Credit card statement / amount due notice - a liability reminder.
  statementDue,
}

/// Classifies [text]. Order matters: the most specific intents win, and past
/// tense debits ("has been debited") always fall through to `MessageIntent.transaction`.
MessageIntent classifyMessage(String text) {
  final t = text.toLowerCase();

  // "has been debited" or "Rs 500 debited ..." (amount directly followed by the verb)
  final pastTenseMoney = RegExp(
    r'\b(?:has|have|was)\s+been\s+(?:debited|credited)'
    r'|(?:rs\.?|inr|₹)\s*[\d,.]+\s+(?:is\s+|was\s+)?(?:debited|credited)\b',
  ).hasMatch(t);

  if (RegExp(r'\b(?:otp|one[\s-]?time\s+password|verification\s+code)\b')
          .hasMatch(t) &&
      !pastTenseMoney) {
    return MessageIntent.otp;
  }
  if (RegExp(
    r'(?:mandate|autopay|auto[\s-]?pay|standing\s+instruction|e-?nach).{0,80}(?:revoked|cancell?ed|paused|deleted|stopped|terminated|deactivated)'
    r'|(?:revoked|cancell?ed|paused|terminated|deactivated).{0,40}(?:mandate|autopay|auto[\s-]?pay)',
  ).hasMatch(t)) {
    return MessageIntent.mandateCancelled;
  }
  if (RegExp(
    r'(?:autopay|auto[\s-]?pay|auto[\s-]?debit|mandate|standing\s+instruction|e-?nach|emi).{0,80}(?:failed|unsuccessful|declined|bounced|insufficient)'
    r'|(?:failed|unsuccessful|declined).{0,40}(?:autopay|auto[\s-]?debit|mandate|e-?nach)',
  ).hasMatch(t)) {
    return MessageIntent.mandateFailed;
  }
  if (RegExp(
    r'(?:mandate|autopay|auto[\s-]?pay|standing\s+instruction|e-?nach).{0,80}(?:created|registered|set\s?up|approved|activated|successfully\s+(?:created|registered))'
    r'|(?:created|registered|approved|activated).{0,40}(?:mandate|autopay|auto[\s-]?pay)',
  ).hasMatch(t)) {
    return MessageIntent.mandateCreated;
  }
  if (RegExp(
    r'\b(?:will\s+be|to\s+be|shall\s+be|is\s+(?:scheduled|due)\s+to\s+be)\s+(?:auto[\s-]?)?(?:debited|charged|deducted|collected)\b'
    r'|\bpre[\s-]?debit\b|\bupcoming\s+(?:auto[\s-]?)?(?:debit|payment|mandate)\b'
    r'|\bscheduled\s+(?:to\s+be\s+)?(?:debit|auto)',
  ).hasMatch(t)) {
    return MessageIntent.preDebit;
  }
  if (RegExp(
        r'\b(?:statement\s+(?:is\s+)?(?:generated|ready)|total\s+(?:amount\s+)?due|min(?:imum)?\s+(?:amount\s+)?due|payment\s+due\s+(?:date|by|on)|bill\s+(?:is\s+)?(?:generated|due))\b',
      ).hasMatch(t) &&
      !pastTenseMoney) {
    return MessageIntent.statementDue;
  }
  return MessageIntent.transaction;
}

/// Details pulled from a mandate-related message.
@immutable
class MandateNotice {
  const MandateNotice({
    required this.intent,
    required this.payee,
    this.amountMinorUnits,
    this.date,
    this.accountMask,
    this.umn,
  });

  final MessageIntent intent;
  final String? payee;
  final int? amountMinorUnits;

  /// Debit date for pre-debit notices when the message states one.
  final DateTime? date;
  final String? accountMask;
  final String? umn;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
};

/// Parses "16-Nov-26", "16/11/2026", "16 Nov 2026". Returns null if absent.
DateTime? extractNoticeDate(String text) {
  int year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);

  final named = RegExp(
    r'\b(\d{1,2})[\s\-/]([A-Za-z]{3})[a-z]*[\s\-/,]*(\d{2,4})\b',
  ).firstMatch(text);
  if (named != null) {
    final m = _months[named.group(2)!.toLowerCase()];
    if (m != null) {
      return DateTime(year(named.group(3)!), m, int.parse(named.group(1)!));
    }
  }
  final numeric = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b')
      .firstMatch(text);
  if (numeric != null) {
    final d = int.parse(numeric.group(1)!);
    final m = int.parse(numeric.group(2)!);
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return DateTime(year(numeric.group(3)!), m, d);
    }
  }
  return null;
}

/// Extracts payee / amount / date / UMN from a mandate-related message.
MandateNotice parseMandateNotice(String text, MessageIntent intent) {
  final amount = RegExp(
    r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  int? minor;
  if (amount != null) {
    final parts = amount.group(1)!.replaceAll(',', '').split('.');
    final frac = parts.length > 1
        ? parts[1].padRight(2, '0').substring(0, 2)
        : '00';
    minor = int.parse(parts[0]) * 100 + int.parse(frac);
  }

  // Payee: "towards Netflix", "to Spotify", "for Netflix", "mandate for Netflix"
  String? payee;
  for (final m in RegExp(
    r'(?:towards|to|for|merchant|payee)\s+([A-Z][A-Za-z0-9&\.\-]*(?:\s+[A-Z][A-Za-z0-9&\.\-]*){0,2})',
  ).allMatches(text)) {
    final candidate = m
        .group(1)!
        .trim()
        .replaceAll(RegExp(r'\s+(?:Rs|INR)\.?$', caseSensitive: false), '');
    final junk = RegExp(
      r'^(?:Rs|INR|UPI|Your|The|A/c|Account|Autopay|Mandate)\b',
      caseSensitive: false,
    ).hasMatch(candidate);
    if (!junk && candidate.length >= 2) {
      payee = candidate;
      break;
    }
  }

  final mask = RegExp(
    r'(?:a\/c|acct|account)\s*[*xX\s]*([0-9]{3,6})\b',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  final umn = RegExp(
    r'\bUMN[:\s]*([A-Za-z0-9@._\-]{6,60})',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);

  return MandateNotice(
    intent: intent,
    payee: payee,
    amountMinorUnits: minor,
    date: extractNoticeDate(text),
    accountMask: mask == null
        ? null
        : (mask.length > 4 ? mask.substring(mask.length - 4) : mask),
    umn: umn,
  );
}
