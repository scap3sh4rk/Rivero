import 'package:flutter/foundation.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Normalized domain representation of a financial transaction extracted
/// by the parsing engine from raw notification or SMS payloads.
@immutable
class ParsedTransaction {
  const ParsedTransaction({
    required this.amountMinorUnits,
    required this.isDebit,
    required this.timestamp,
    required this.confidenceScore,
    required this.rawPayload,
    required this.suggestedTransactionType,
    required this.suggestedRole,
    this.accountMask,
    this.accountType,
    this.merchant,
    this.category,
    this.referenceNumber,
    this.balanceMinorUnits,
    this.senderHeader,
    this.financialInstitution,
  }) : assert(
         amountMinorUnits > 0,
         'amountMinorUnits must be strictly positive',
       ),
       assert(
         confidenceScore >= 0.0 && confidenceScore <= 1.0,
         'confidenceScore must be between 0.0 and 1.0',
       );

  /// Absolute monetary value in minor units (paise).
  final int amountMinorUnits;

  /// True for outflows/debits; false for inflows/credits.
  final bool isDebit;

  /// Timestamp of the transaction extracted from message or received timestamp.
  final DateTime timestamp;

  /// Confidence score computed by the regex/classifier engine (0.0 to 1.0).
  final double confidenceScore;

  /// Original raw message or notification payload.
  final String rawPayload;

  /// Financial classification determined by parser rules.
  final TransactionType suggestedTransactionType;

  /// Destination or source budget role (e.g. EXPENSE, SAVINGS, LIABILITY_CC).
  final AccountRole suggestedRole;

  /// Last 3-4 digits of the payment instrument (bank account or card).
  final String? accountMask;

  /// Type of payment instrument: "A/C", "Card", "UPI", "Wallet".
  final String? accountType;

  /// Cleaned merchant, counterparty, or beneficiary name.
  final String? merchant;

  /// Spending category inferred from merchant or keywords.
  final String? category;

  /// Unique bank or UPI transaction reference (UTR, UPI RRN, 12-digit ID).
  final String? referenceNumber;

  /// Available account balance reported in the message (if any), in minor units (paise).
  final int? balanceMinorUnits;

  /// Sender header (TRAI DLT) or originating package name.
  final String? senderHeader;

  /// Human-readable bank or payment app name (e.g. "HDFC Bank", "Google Pay").
  final String? financialInstitution;

  /// True if confidence meets the threshold for automatic confirmation without manual review.
  bool get isHighConfidence => confidenceScore >= 0.85;

  /// True if confidence is sufficient for triage review but below automatic threshold.
  bool get isMediumConfidence =>
      confidenceScore >= 0.60 && confidenceScore < 0.85;

  /// True if confidence is below 0.60, requiring quarantine (EC-10).
  bool get isLowConfidence => confidenceScore < 0.60;

  ParsedTransaction copyWith({
    int? amountMinorUnits,
    bool? isDebit,
    DateTime? timestamp,
    double? confidenceScore,
    String? rawPayload,
    TransactionType? suggestedTransactionType,
    AccountRole? suggestedRole,
    String? accountMask,
    String? accountType,
    String? merchant,
    String? category,
    String? referenceNumber,
    int? balanceMinorUnits,
    String? senderHeader,
    String? financialInstitution,
  }) {
    return ParsedTransaction(
      amountMinorUnits: amountMinorUnits ?? this.amountMinorUnits,
      isDebit: isDebit ?? this.isDebit,
      timestamp: timestamp ?? this.timestamp,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      rawPayload: rawPayload ?? this.rawPayload,
      suggestedTransactionType:
          suggestedTransactionType ?? this.suggestedTransactionType,
      suggestedRole: suggestedRole ?? this.suggestedRole,
      accountMask: accountMask ?? this.accountMask,
      accountType: accountType ?? this.accountType,
      merchant: merchant ?? this.merchant,
      category: category ?? this.category,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      balanceMinorUnits: balanceMinorUnits ?? this.balanceMinorUnits,
      senderHeader: senderHeader ?? this.senderHeader,
      financialInstitution: financialInstitution ?? this.financialInstitution,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedTransaction &&
          runtimeType == other.runtimeType &&
          amountMinorUnits == other.amountMinorUnits &&
          isDebit == other.isDebit &&
          timestamp == other.timestamp &&
          (confidenceScore - other.confidenceScore).abs() < 1e-6 &&
          rawPayload == other.rawPayload &&
          suggestedTransactionType == other.suggestedTransactionType &&
          suggestedRole == other.suggestedRole &&
          accountMask == other.accountMask &&
          accountType == other.accountType &&
          merchant == other.merchant &&
          category == other.category &&
          referenceNumber == other.referenceNumber &&
          balanceMinorUnits == other.balanceMinorUnits &&
          senderHeader == other.senderHeader &&
          financialInstitution == other.financialInstitution;

  @override
  int get hashCode => Object.hash(
    amountMinorUnits,
    isDebit,
    timestamp,
    confidenceScore,
    rawPayload,
    suggestedTransactionType,
    suggestedRole,
    accountMask,
    accountType,
    merchant,
    category,
    referenceNumber,
    balanceMinorUnits,
    senderHeader,
    financialInstitution,
  );

  @override
  String toString() {
    return 'ParsedTransaction(amount: $amountMinorUnits paise, '
        'isDebit: $isDebit, merchant: $merchant, mask: $accountMask, '
        'ref: $referenceNumber, confidence: ${(confidenceScore * 100).toStringAsFixed(1)}%)';
  }
}
