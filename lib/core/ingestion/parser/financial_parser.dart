import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/message_intent.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';

/// Production-grade financial parser for Indian banking SMS and UPI app push notifications.
///
/// Implements a 3-stage extraction pipeline:
/// 1. Fast heuristic filter (rejects non-financial messages in O(1)).
/// 2. Entity extraction (monetary amounts in paise, debit/credit flow, account mask,
///    counterparty, UTR/RRN reference, balance).
/// 3. Normalization and confidence scoring.
class FinancialParser {
  const FinancialParser({this.dltValidator = const TraiDltValidator()});

  final TraiDltValidator dltValidator;

  // Fast filter keywords
  static final RegExp _financialKeywordRegex = RegExp(
    r'\b(?:debited|credited|spent|paid|payment|withdrawn|transferred|transfer|sent|received|refund|refunded|reversed|mandate|autopay|auto-debit|emi|salary)\b',
    caseSensitive: false,
  );

  static final RegExp _currencyIndicatorRegex = RegExp(
    r'(?:Rs\.?|INR|₹)',
    caseSensitive: false,
  );

  // Monetary amount regex: "Rs 450.00", "INR 1,299.50", "₹500", "Rs. 25,000"
  static final RegExp _amountRegex = RegExp(
    r'(?:(?:Rs\.?|INR|₹)\s*|(?:\b))([\d,]+(?:\.\d{1,2})?)\s*(?:(?:Rs\.?|INR|₹)|\b)',
    caseSensitive: false,
  );

  // Contextual amount match: strictly prefixed by currency symbol
  static final RegExp _strictAmountRegex = RegExp(
    r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Banks such as SBI often omit the currency: "debited by 500.0",
  // "credited with 1,250.50", "debited for 250".
  static final RegExp _verbAmountRegex = RegExp(
    r'\b(?:debited|credited|withdrawn|transferred|deducted)\s+(?:by|for|with|of)\s+(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Direction patterns
  static final RegExp _debitRegex = RegExp(
    r'\b(?:debited|spent|paid|withdrawn|transferred to|transfer to|sent to|purchase of|used at|auto-debited|auto debit)\b',
    caseSensitive: false,
  );

  /// Bank shorthand: "Dr Rs25.00" (money out), "Cr Rs500" (money in), as
  /// Union Bank and others write it. Only right before an amount, so a
  /// "Dr." (doctor) payee is not read as a debit.
  static final RegExp _drAmountRegex = RegExp(
    r'\bDr\.?\s*(?:Rs\.?|INR|₹)\s*\d',
    caseSensitive: false,
  );
  static final RegExp _crAmountRegex = RegExp(
    r'\bCr\.?\s*(?:Rs\.?|INR|₹)\s*\d',
    caseSensitive: false,
  );

  /// "by MB 631977745590", "by UPI 512345678901", "via IMPS 4567...": the
  /// bank's reference for the payment.
  static final RegExp _byChannelRefRegex = RegExp(
    r'\b(?:by|via)\s+(?:MB|UPI|IMPS|NEFT|RTGS|NB)\s*[:\-/]?\s*(\d{6,16})\b',
    caseSensitive: false,
  );

  /// "Fv.IRANI", "Fvg RAVI KUMAR", "favouring ACME": who was paid.
  static final RegExp _favouringRegex = RegExp(
    r'\b(?:Fvg?\.?|favou?ring)\s*([A-Za-z][A-Za-z0-9 &\.\-]{1,30}?)(?=\s*[,;]|\.\s|\s+(?:bal|avl|on|ref|not)\b|$)',
    caseSensitive: false,
  );

  static final RegExp _creditRegex = RegExp(
    r'\b(?:credited|received|deposited|refunded|reversed|cashback)\b',
    caseSensitive: false,
  );

  static final RegExp _salaryRegex = RegExp(
    r'\b(?:salary)\b',
    caseSensitive: false,
  );

  static final RegExp _creditCardRegex = RegExp(
    r'\b(?:credit card|card ending|on your card)\b',
    caseSensitive: false,
  );

  static final RegExp _ccSettlementRegex = RegExp(
    r'\b(?:received towards your.*credit card|payment.*received towards.*card)\b',
    caseSensitive: false,
  );

  // Bank-side leg of paying a card bill: "towards ICICI Credit Card XX7102 bill"
  static final RegExp _ccBillPaymentRegex = RegExp(
    r'(?:\b(?:towards|for|to)\b[^.]{0,50}credit\s*card|credit\s*card\s*(?:bill|payment|dues?)|\bcc\s*(?:bill|payment))',
    caseSensitive: false,
  );

  static final RegExp _cardSpendRegex = RegExp(
    r'\b(?:spent|purchase|used\s+at|swiped|pos|txn\s+of)\b',
    caseSensitive: false,
  );

  static final RegExp _atmRegex = RegExp(
    r'\b(?:atm|cash withdrawal)\b',
    caseSensitive: false,
  );

  // Account mask patterns: "a/c **1234", "Acct XX5678", "card ending 4321", "A/C XXXXX123456"
  static final RegExp _accountMaskRegex = RegExp(
    r'(?:(?:a\/c|acct|account|card)\s*(?:no\.?|number)?\s*[*xX\s]*|ending\s+(?:in\s+)?|ending\s+[*xX\s]*)([0-9]{3,6})\b',
    caseSensitive: false,
  );

  // Reference number / UTR / RRN: "UPI Ref No 431712345678", "UPI/431899123456", "Ref no 431987654321"
  static final RegExp _referenceNumberRegex = RegExp(
    r'(?:(?:UPI(?:\/|\s+Ref(?:\s*No)?|\s*RRN)?|UTR|RRN|Ref\s*(?:no\.?|num)?|Txn\s*ID)\s*[:\-\/\s]*)([0-9a-zA-Z]{6,16})\b',
    caseSensitive: false,
  );

  // Balance regex: "Avl bal: Rs 45,210.50", "Avail Bal: INR 12,000.00", "Bal Rs.14,500.00"
  static final RegExp _balanceRegex = RegExp(
    r'(?:(?:avl|avail(?:able)?|total)\s*bal(?:ance)?|bal(?:ance)?)\s*[:\-\s]*(?:is\s*)?(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Counterparty patterns
  static final RegExp _vpaMerchantRegex = RegExp(
    r'(?:to\s+(?:VPA\s+)?|towards\s+|at\s+)([a-zA-Z0-9_\.\-]{2,40}@[a-zA-Z0-9]{2,15})',
    caseSensitive: false,
  );

  static final RegExp _infoMerchantRegex = RegExp(
    r'(?:info:\s*(?:bil\/onl\/|onl\/|upi\/)?)([A-Za-z0-9\s&\.\-_]{2,30}?)(?:\s+(?:on|ref|avl|bal|using|via|with|upi|\.|\,)|$)',
    caseSensitive: false,
  );

  static final RegExp _generalMerchantRegex = RegExp(
    r'(?:to\s+|at\s+|towards\s+|transfer\s+to\s+|payment\s+(?:of\s+[^\s]+\s+)?to\s+|paid\s+(?:Rs\.?|INR|₹)?\s*[\d,.]*\s*to\s+)([A-Za-z0-9\s&\.\-_]{2,30}?)(?:\s+(?:on|ref|avl|bal|using|via|with|was|is|upi|\.|\,)|$)',
    caseSensitive: false,
  );

  /// Parses an incoming [RawNotification] into a normalized [ParsedTransaction].
  ///
  /// Returns `null` if the message is deemed non-financial.
  ParsedTransaction? parse(RawNotification notification) {
    var text = notification.body;
    // Payment apps often put the amount in the notification title ("Paid
    // ₹500 to Rahul") and only the app name in the body.
    final title = notification.title;
    if (_extractAmount(text) == null &&
        title != null &&
        _extractAmount(title) != null) {
      text = '$title . $text'; // the lone dot ends the merchant name
    }

    // Reminders, OTPs, mandate lifecycle and statement notices are not money
    // movements; the ingestion service handles them separately.
    if (classify(text) != MessageIntent.transaction) return null;

    // Stage 1: Fast filter
    if (!_isPotentiallyFinancial(text, notification)) {
      return null;
    }

    // Stage 2: Entity extraction
    final amountMinorUnits = _extractAmount(text);
    if (amountMinorUnits == null || amountMinorUnits <= 0) {
      return null;
    }

    final isDebit = _determineDirection(text);
    final accountMask = _extractAccountMask(text);
    final accountType = _determineAccountType(text);
    final referenceNumber = _extractReferenceNumber(text);
    final balanceMinorUnits = _extractBalance(text);
    final merchant =
        _extractMerchant(text, notification.title) ??
        (isDebit ? null : _extractPayer(text));

    final institution = dltValidator.resolveFinancialInstitutionName(
      senderHeader: notification.sender,
      packageName: notification.packageName,
    );

    final txType = _determineTransactionType(
      text: text,
      isDebit: isDebit,
      isAtm: _atmRegex.hasMatch(text),
      isCreditCard: _creditCardRegex.hasMatch(text),
      isSalary: _salaryRegex.hasMatch(text),
      isCcSettlement:
          _ccSettlementRegex.hasMatch(text) ||
          (isDebit &&
              _ccBillPaymentRegex.hasMatch(text) &&
              !_cardSpendRegex.hasMatch(text)),
    );

    final role = _determineRole(txType, isDebit);

    // Stage 3: Confidence scoring
    final confidence = _computeConfidence(
      hasAmount: true,
      hasDirection: true,
      hasAccountMask: accountMask != null,
      hasReferenceNumber: referenceNumber != null,
      hasMerchant: merchant != null,
      hasValidSender: dltValidator.isFinancialSender(
        senderHeader: notification.sender,
        packageName: notification.packageName,
      ),
    );

    final category = _inferCategory(merchant, text);

    return ParsedTransaction(
      amountMinorUnits: amountMinorUnits,
      isDebit: isDebit,
      timestamp: notification.receivedAt,
      confidenceScore: confidence,
      rawPayload: text,
      suggestedTransactionType: txType,
      suggestedRole: role,
      accountMask: accountMask,
      accountType: accountType,
      merchant: merchant,
      category: category,
      referenceNumber: referenceNumber,
      balanceMinorUnits: balanceMinorUnits,
      senderHeader: notification.sender ?? notification.packageName,
      financialInstitution: institution,
    );
  }

  /// What this message is about (see `MessageIntent`).
  MessageIntent classify(String text) => classifyMessage(text);

  /// Details of a mandate / pre-debit message.
  MandateNotice parseNotice(String text, MessageIntent intent) =>
      parseMandateNotice(text, intent);

  bool _isPotentiallyFinancial(String text, RawNotification notification) {
    if (notification.packageName != null &&
        dltValidator.isFinancialSender(packageName: notification.packageName)) {
      return true;
    }

    if (notification.sender != null &&
        dltValidator.isFinancialSender(senderHeader: notification.sender)) {
      return true;
    }

    final hasKeyword =
        _financialKeywordRegex.hasMatch(text) ||
        _drAmountRegex.hasMatch(text) ||
        _crAmountRegex.hasMatch(text);
    final hasCurrency =
        _currencyIndicatorRegex.hasMatch(text) ||
        _verbAmountRegex.hasMatch(text);
    return hasKeyword && hasCurrency;
  }

  /// Parses monetary amounts into integer minor units (paise) using pure integer arithmetic.
  int? _extractAmount(String text) {
    final match =
        _strictAmountRegex.firstMatch(text) ??
        _verbAmountRegex.firstMatch(text) ??
        _amountRegex.firstMatch(text);
    if (match == null) return null;

    final raw = match.group(1)?.replaceAll(',', '').trim();
    if (raw == null || raw.isEmpty) return null;

    return _parseCurrencyToPaise(raw);
  }

  int? _parseCurrencyToPaise(String amountStr) {
    try {
      final parts = amountStr.split('.');
      final whole = int.parse(parts[0]);
      // A "balance" or reference number glued to Rs/INR must not overflow.
      if (whole > 1000000000) return null;
      var fraction = 0;
      if (parts.length > 1) {
        final fracPart = parts[1].padRight(2, '0').substring(0, 2);
        fraction = int.parse(fracPart);
      }
      return (whole * 100) + fraction;
    } on FormatException catch (_) {
      return null;
    }
  }

  int? _extractBalance(String text) {
    final match = _balanceRegex.firstMatch(text);
    if (match == null) return null;

    final raw = match.group(1)?.replaceAll(',', '').trim();
    if (raw == null || raw.isEmpty) return null;

    return _parseCurrencyToPaise(raw);
  }

  bool _determineDirection(String text) {
    if (_salaryRegex.hasMatch(text)) {
      return false; // Inflow / credit
    }
    if (_creditRegex.hasMatch(text) && !_debitRegex.hasMatch(text)) {
      return false; // Inflow
    }
    if (_crAmountRegex.hasMatch(text) && !_drAmountRegex.hasMatch(text)) {
      return false; // "Cr Rs500"
    }
    return true; // Outflow / debit default
  }

  String? _extractAccountMask(String text) {
    final match = _accountMaskRegex.firstMatch(text);
    if (match == null) return null;
    final digits = match.group(1);
    if (digits == null) return null;
    // Take the last 4 digits if longer
    return digits.length > 4 ? digits.substring(digits.length - 4) : digits;
  }

  String? _determineAccountType(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('credit card') || lower.contains('card ending')) {
      return 'Card';
    } else if (lower.contains('wallet')) {
      return 'Wallet';
    } else if (lower.contains('upi')) {
      return 'UPI';
    }
    return 'A/C';
  }

  String? _extractReferenceNumber(String text) {
    final match =
        _referenceNumberRegex.firstMatch(text) ??
        _byChannelRefRegex.firstMatch(text);
    return match?.group(1);
  }

  String? _extractMerchant(String text, String? title) {
    // 0. "Fv.IRANI": the bank names who was paid.
    final fav = _favouringRegex.firstMatch(text)?.group(1)?.trim();
    if (fav != null && fav.length >= 2 && !_isCommonExclusion(fav)) {
      return _cleanMerchantName(fav);
    }

    // 1. Try VPA match: "to VPA swiggy@hdfcbank" -> "Swiggy"
    final vpaMatch = _vpaMerchantRegex.firstMatch(text);
    if (vpaMatch != null) {
      final vpa = vpaMatch.group(1);
      if (vpa != null) {
        final prefix = vpa.split('@')[0];
        return _cleanMerchantName(prefix);
      }
    }

    // 2. Try ICICI / Info match: "Info: BIL/ONL/Amazon Pay" -> "Amazon Pay"
    final infoMatch = _infoMerchantRegex.firstMatch(text);
    if (infoMatch != null) {
      final m = infoMatch.group(1);
      if (m != null && m.trim().length >= 2) {
        final clean = _cleanMerchantName(m);
        if (!_isCommonExclusion(clean)) {
          return clean;
        }
      }
    }

    // 3. Try general merchant pattern
    final generalMatch = _generalMerchantRegex.firstMatch(text);
    if (generalMatch != null) {
      final m = generalMatch.group(1);
      if (m != null && m.trim().length >= 2) {
        final clean = _cleanMerchantName(m);
        if (!_isCommonExclusion(clean)) {
          return clean;
        }
      }
    }

    // 3. Fallback to title if title mentions recipient
    if (title != null && title.isNotEmpty) {
      final cleanTitle = _cleanMerchantName(title);
      if (!_isCommonExclusion(cleanTitle)) {
        return cleanTitle;
      }
    }

    return null;
  }

  /// Who sent money that came in: "... from PARTHIV K Ref ...". Only used
  /// for credits, when nothing better was found.
  static final RegExp _payerRegex = RegExp(
    r'\bfrom\s+([A-Za-z][A-Za-z\s\.]{1,30}?)(?=\s+(?:on|ref|avl|bal|imps|neft|rtgs|upi|via|info)\b|[\.,:;]|$)',
    caseSensitive: false,
  );

  String? _extractPayer(String text) {
    final m = _payerRegex.firstMatch(text)?.group(1)?.trim();
    if (m == null || m.length < 2) return null;
    if (RegExp(
      r'^(?:a\/c|acct|account|your|ac|card|bank|wallet)\b',
      caseSensitive: false,
    ).hasMatch(m)) {
      return null;
    }
    return _cleanMerchantName(m);
  }

  String _cleanMerchantName(String raw) {
    return raw
        .replaceAll(
          RegExp(r'^(?:vpa\s+|bil\/onl\/|onl\/|upi\/)', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[\.\-_/]+$'), '')
        .trim();
  }

  bool _isCommonExclusion(String name) {
    final lower = name.toLowerCase();
    // A phone number or a reference is not a payee ("SMS BLOCK to 88796...").
    if (RegExp(r'^[\d\s+\-]+$').hasMatch(lower)) return true;
    return lower == 'rs' ||
        lower == 'inr' ||
        lower == 'account' ||
        lower == 'a/c' ||
        lower == 'card' ||
        lower == 'your' ||
        lower == 'successful' ||
        lower == 'payment';
  }

  TransactionType _determineTransactionType({
    required String text,
    required bool isDebit,
    required bool isAtm,
    required bool isCreditCard,
    required bool isSalary,
    required bool isCcSettlement,
  }) {
    if (isSalary) {
      return TransactionType.income;
    }
    if (isCcSettlement) {
      return TransactionType.creditCardSettlement;
    }
    if (isAtm) {
      return TransactionType.atmWithdrawal;
    }
    if (isCreditCard) {
      return isDebit
          ? TransactionType.creditCardPurchase
          : TransactionType.refund;
    }
    if (text.toLowerCase().contains('refund')) {
      return TransactionType.refund;
    }
    if (text.toLowerCase().contains('reversal')) {
      return TransactionType.reversal;
    }

    return isDebit ? TransactionType.expense : TransactionType.income;
  }

  AccountRole _determineRole(TransactionType type, bool isDebit) {
    switch (type) {
      case TransactionType.income:
        return AccountRole.salaryRoot;
      case TransactionType.creditCardPurchase:
      case TransactionType.creditCardSettlement:
        return AccountRole.liabilityCc;
      case TransactionType.atmWithdrawal:
        return AccountRole.virtualWallet;
      case TransactionType.investmentContribution:
      case TransactionType.investmentRedemption:
        return AccountRole.investment;
      case TransactionType.expense:
      case TransactionType.refund:
      case TransactionType.reversal:
      case TransactionType.internalTransfer:
      case TransactionType.bucketFunding:
      case TransactionType.reimbursement:
      case TransactionType.cashExpenditure:
      case TransactionType.walletTopup:
      case TransactionType.balanceAdjustment:
      case TransactionType.lending:
      case TransactionType.borrowing:
      case TransactionType.repayment:
      case TransactionType.planTransfer:
        return isDebit ? AccountRole.expense : AccountRole.savings;
    }
  }

  double _computeConfidence({
    required bool hasAmount,
    required bool hasDirection,
    required bool hasAccountMask,
    required bool hasReferenceNumber,
    required bool hasMerchant,
    required bool hasValidSender,
  }) {
    var score = 0.0;
    if (hasAmount) score += 0.35;
    if (hasDirection) score += 0.20;
    if (hasAccountMask) score += 0.15;
    if (hasReferenceNumber) score += 0.15;
    if (hasMerchant) score += 0.10;
    if (hasValidSender) score += 0.05;

    return score > 1.0 ? 1.0 : score;
  }

  String? _inferCategory(String? merchant, String text) {
    final lower = '${merchant ?? ''} $text'.toLowerCase();

    if (lower.contains('swiggy') ||
        lower.contains('zomato') ||
        lower.contains('starbucks') ||
        lower.contains('mcdonald') ||
        lower.contains('restaurant') ||
        lower.contains('food')) {
      return 'Food & Dining';
    }
    if (lower.contains('amazon') ||
        lower.contains('flipkart') ||
        lower.contains('myntra') ||
        lower.contains('zara') ||
        lower.contains('shopping')) {
      return 'Shopping';
    }
    if (lower.contains('uber') ||
        lower.contains('ola') ||
        lower.contains('fuel') ||
        lower.contains('petrol') ||
        lower.contains('metro')) {
      return 'Transportation';
    }
    if (lower.contains('netflix') ||
        lower.contains('spotify') ||
        lower.contains('hotstar') ||
        lower.contains('prime video')) {
      return 'Entertainment & Subscriptions';
    }
    if (lower.contains('zerodha') ||
        lower.contains('groww') ||
        lower.contains('sip') ||
        lower.contains('mutual fund')) {
      return 'Investment';
    }

    return 'General Expense';
  }
}
