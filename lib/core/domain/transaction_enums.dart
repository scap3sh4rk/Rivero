/// Transaction types distinguishing all personal financial movements.
enum TransactionType {
  income,
  expense,
  internalTransfer,
  bucketFunding,
  investmentContribution,
  investmentRedemption,
  creditCardPurchase,
  creditCardSettlement,
  refund,
  reversal,
  reimbursement,
  atmWithdrawal,
  cashExpenditure,
  walletTopup,
  balanceAdjustment,

  /// Money lent to someone: leaves the account, is not spending.
  lending,

  /// Money borrowed from someone: arrives in the account, is not income.
  borrowing,

  /// Paying back money you borrowed: leaves the account, is not spending
  /// (it was spent when you borrowed it).
  repayment,

  /// A payment the salary plan makes out of the salary account for a
  /// category such as Rent or Family. Real spending for reports, but it never
  /// touches the everyday spending budget.
  planTransfer,
}

/// Explicit lifecycle states for transactions in the ledger.
enum TransactionState {
  detected,
  parsed,
  needsReview,
  confirmed,
  reconciled,
  duplicate,
  reversed,
  failed,
  ignored,
}

/// Recurring frequency for UPI Autopay and e-NACH commitments.
enum MandateFrequency {
  weekly,
  monthly,
  quarterly,
  semiAnnual,
  annual,
  asPresented,
}

/// State of an automated payment mandate.
enum MandateStatus { registered, active, paused, revoked, expired, cancelled }

/// Ingestion channel through which the transaction was captured.
enum IngestionChannel {
  notificationAndroid,
  shortcutIos,
  manualEntry,
  statementImport,
}

/// Parse and classification status for raw message logs.
enum ParseStatus { parsed, quarantined, failed, ignored }

/// Why someone owes the user money.
enum DueKind {
  /// Their share of a bill the user paid.
  split,

  /// Cash or a transfer the user lent them.
  lent,

  /// Money the user borrowed and has to pay back (they owe the other person).
  borrowed,
}

/// Lifecycle of money owed to the user.
enum DueStatus { open, settled, writtenOff }

/// What an autopay is for, so the list shows it at a glance.
enum MandateKind {
  sip,
  subscription,
  emi,
  insurance,
  utility,
  rent,
  other;

  String get label => switch (this) {
    sip => 'SIP',
    subscription => 'Subscription',
    emi => 'Loan EMI',
    insurance => 'Insurance',
    utility => 'Bill',
    rent => 'Rent',
    other => 'Autopay',
  };

  /// A best guess from the payee's name, for autopays added before kinds
  /// existed or found in bank messages ("Other" when unsure).
  static MandateKind guess(String payee) {
    final p = payee.toLowerCase();
    // Whole words only: "premium" is not an "emi".
    bool has(List<String> w) =>
        w.any((k) => RegExp('\\b${RegExp.escape(k.trim())}\\b').hasMatch(p));
    if (has([
      'sip',
      'mutual fund',
      ' mf',
      'mf ',
      'amc',
      'groww',
      'zerodha',
      'coin',
      'kuvera',
      'nippon',
      'axis mf',
      'hdfc mf',
      'sbi mf',
    ])) {
      return sip;
    }
    if (has(['emi', 'loan', 'bajaj fin', 'finance'])) return emi;
    if (has(['insurance', 'lic', 'policy', 'premium', 'life', 'health'])) {
      return insurance;
    }
    if (has(['rent', 'landlord', 'nobroker'])) return rent;
    if (has([
      'netflix',
      'spotify',
      'prime',
      'youtube',
      'hotstar',
      'apple',
      'google one',
      'icloud',
      'subscription',
      'zee5',
      'sonyliv',
      'jiocinema',
      'audible',
      'swiggy one',
      'zomato gold',
    ])) {
      return subscription;
    }
    if (has([
      'electricity',
      'bescom',
      'tneb',
      'msedcl',
      'broadband',
      'fiber',
      'airtel',
      'jio',
      'vodafone',
      'vi ',
      'act ',
      'gas',
      'water',
      'dth',
      'tata play',
      'mobile',
      'postpaid',
      'bill',
    ])) {
      return utility;
    }
    return other;
  }
}
