import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';

/// One card's bill in words: which account pays it and whether that account
/// holds enough. Cards paid from the same account are judged together, so
/// the line names the others and the total ("with HDFC, ₹12,000 in all").
/// Null when nothing is owed.
({String text, bool ok})? billStatus(
  CardBills bills,
  PhysicalAccount card,
  String Function(int) money,
) {
  final a = bills.byCard[card.id];
  if (a == null || card.balanceMinorUnits >= 0) return null;
  final payer = bills.payerOf[card.id];
  final from = payer == null ? 'your other accounts' : payer.name;
  final others = [
    for (final c in bills.sharing[card.id] ?? const <PhysicalAccount>[])
      if (c.id != card.id && c.balanceMinorUnits < 0) c.name,
  ];
  final group = others.isEmpty
      ? ''
      : ', with ${others.join(', ')} (${money(a.owed)} in all)';
  return (
    text: a.canPay
        ? 'From $from$group: enough'
        : 'From $from$group: short by ${money(a.shortBy)}',
    ok: a.canPay,
  );
}
