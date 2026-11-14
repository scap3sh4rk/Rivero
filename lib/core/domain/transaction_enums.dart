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
