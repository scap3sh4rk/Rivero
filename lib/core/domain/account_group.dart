import 'dart:convert';

import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';

/// The sections of the Accounts page. Every account belongs to exactly one.
enum AccountGroup {
  bank('Bank & cash'),
  investment('Investments & demat'),
  deposit('Fixed deposits'),
  card('Credit cards'),
  loan('Loans');

  AccountGroup(this.label);
  final String label;

  static AccountGroup of(PhysicalAccount a) {
    final t = a.accountType.toLowerCase();
    if (a.isLiability) {
      return StandardAccountTypes.isLongTermDebt(a.accountType) ? loan : card;
    }
    if (isFixedDeposit(a)) return deposit;
    if (t.contains('invest') ||
        t.contains('demat') ||
        t.contains('stock') ||
        t.contains('mutual') ||
        t.contains('ppf') ||
        t.contains('nps')) {
      return investment;
    }
    return bank;
  }

  static bool isFixedDeposit(PhysicalAccount a) =>
      !a.isLiability &&
      (a.accountType.toLowerCase().contains('fixed deposit') ||
          a.accountType.toLowerCase().contains('recurring deposit') ||
          a.fdMaturityDate != null);
}

/// The user's order of the sections and which are folded away.
class AccountGroupPrefs {
  const AccountGroupPrefs({
    this.order = AccountGroup.values,
    this.collapsed = const {},
  });

  factory AccountGroupPrefs.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const AccountGroupPrefs();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      AccountGroup? byName(Object? n) =>
          AccountGroup.values.where((g) => g.name == n).firstOrNull;
      final order = [
        for (final n in (j['order'] as List? ?? const [])) ?byName(n),
      ];
      // Sections added in later versions go at the end.
      for (final g in AccountGroup.values) {
        if (!order.contains(g)) order.add(g);
      }
      return AccountGroupPrefs(
        order: order,
        collapsed: {
          for (final n in (j['collapsed'] as List? ?? const [])) ?byName(n),
        },
      );
    } on FormatException {
      return const AccountGroupPrefs();
    }
  }

  final List<AccountGroup> order;
  final Set<AccountGroup> collapsed;

  String toJson() => jsonEncode({
    'order': [for (final g in order) g.name],
    'collapsed': [for (final g in collapsed) g.name],
  });

  AccountGroupPrefs toggled(AccountGroup g) => AccountGroupPrefs(
    order: order,
    collapsed: collapsed.contains(g)
        ? ({...collapsed}..remove(g))
        : {...collapsed, g},
  );

  AccountGroupPrefs reordered(List<AccountGroup> next) =>
      AccountGroupPrefs(order: next, collapsed: collapsed);
}

/// Fixed deposit maths in integer paise: interest compounds every quarter
/// (as Indian banks do), and simple interest runs for the part-quarter at
/// the end.
abstract final class FixedDeposit {
  /// What [principal] grows to by [on] at [rateBps] (7.25% = 725) a year,
  /// from [start].
  static int valueOn({
    required int principal,
    required int rateBps,
    required DateTime start,
    required DateTime on,
  }) {
    if (principal <= 0 || rateBps <= 0 || !on.isAfter(start)) return principal;
    var value = principal;
    var from = start;
    for (var q = 1; ; q++) {
      final next = addMonths(start, 3 * q);
      if (next.isAfter(on)) break;
      value += (value * rateBps + 20000) ~/ 40000; // rate / 4, rounded
      from = next;
    }
    final days = on.difference(from).inDays;
    return value + (value * rateBps * days + 1825000) ~/ 3650000; // simple
  }

  /// [a]'s value at maturity (the balance when no rate or dates are set).
  static int maturityValue(PhysicalAccount a) =>
      a.fdRateBps == null || a.fdStartDate == null || a.fdMaturityDate == null
      ? a.balanceMinorUnits
      : valueOn(
          principal: a.balanceMinorUnits,
          rateBps: a.fdRateBps!,
          start: a.fdStartDate!,
          on: a.fdMaturityDate!,
        );

  /// [a]'s value today, with the interest earned so far.
  static int valueToday(PhysicalAccount a, DateTime now) =>
      a.fdRateBps == null || a.fdStartDate == null
      ? a.balanceMinorUnits
      : valueOn(
          principal: a.balanceMinorUnits,
          rateBps: a.fdRateBps!,
          start: a.fdStartDate!,
          on: a.fdMaturityDate != null && now.isAfter(a.fdMaturityDate!)
              ? a.fdMaturityDate!
              : now,
        );
}
