import 'package:flutter/foundation.dart';

/// Defines how an allocation rule computes its target amount.
enum AllocationType {
  /// A fixed monetary amount in minor units (paise).
  fixed,

  /// A percentage calculated directly from the total incoming salary amount.
  percentageOfSalary,

  /// A percentage calculated from whatever balance remains in the waterfall
  /// after previous priority allocations have executed.
  percentageOfRemaining,
}

/// A declarative rule defining how money from an incoming salary credit
/// should be allocated into a specific virtual allocation bucket.
@immutable
class AllocationRule {
  const AllocationRule({
    required this.id,
    required this.bucketId,
    required this.type,
    this.fixedAmount,
    this.percentage,
    this.priority = 100,
    this.cap,
    this.isMandatory = true,
  }) : assert(
         type != AllocationType.fixed ||
             (fixedAmount != null && fixedAmount >= 0),
         'fixedAmount must be non-negative when type is fixed',
       ),
       assert(
         type == AllocationType.fixed ||
             (percentage != null && percentage > 0 && percentage <= 100),
         'percentage must be between 0 and 100 for percentage-based allocations',
       ),
       assert(cap == null || cap >= 0, 'cap must be non-negative if specified'),
       assert(priority >= 0, 'priority must be non-negative');

  /// Unique identifier of this allocation rule.
  final String id;

  /// ID of the destination allocation bucket.
  final String bucketId;

  /// The mechanism by which the allocation amount is calculated.
  final AllocationType type;

  /// Fixed minor units (paise) to allocate. Used when [type] is [AllocationType.fixed].
  final int? fixedAmount;

  /// Percentage (0.0 < p <= 100.0) of salary or remaining funds.
  final double? percentage;

  /// Execution priority in the waterfall. Lower numbers run first.
  final int priority;

  /// Optional maximum cap in minor units (paise) that can be allocated by this rule.
  final int? cap;

  /// Whether this allocation is essential. If salary is insufficient to fund
  /// a mandatory rule, a shortfall is flagged in the allocation result.
  final bool isMandatory;

  AllocationRule copyWith({
    String? id,
    String? bucketId,
    AllocationType? type,
    int? fixedAmount,
    double? percentage,
    int? priority,
    int? cap,
    bool? isMandatory,
  }) {
    return AllocationRule(
      id: id ?? this.id,
      bucketId: bucketId ?? this.bucketId,
      type: type ?? this.type,
      fixedAmount: fixedAmount ?? this.fixedAmount,
      percentage: percentage ?? this.percentage,
      priority: priority ?? this.priority,
      cap: cap ?? this.cap,
      isMandatory: isMandatory ?? this.isMandatory,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllocationRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          bucketId == other.bucketId &&
          type == other.type &&
          fixedAmount == other.fixedAmount &&
          percentage == other.percentage &&
          priority == other.priority &&
          cap == other.cap &&
          isMandatory == other.isMandatory;

  @override
  int get hashCode => Object.hash(
    id,
    bucketId,
    type,
    fixedAmount,
    percentage,
    priority,
    cap,
    isMandatory,
  );

  @override
  String toString() {
    return 'AllocationRule(id: $id, bucket: $bucketId, type: $type, '
        'fixed: $fixedAmount, %: $percentage, priority: $priority, cap: $cap)';
  }
}
