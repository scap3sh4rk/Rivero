/// Hides personal details in a bank message before it is shared in a public
/// report, keeping the wording and shape the parser cares about:
/// every digit becomes 1 ("Rs 4,250.00" -> "Rs 1,111.11", "XX4321" ->
/// "XX1111"), UPI IDs and emails become name@bank, and capitalised words
/// after to/from/by/at become NAME. The user still checks it before sending.
String redactMessage(String text) {
  var s = text.replaceAllMapped(
    RegExp(r'[\w.\-]+@([\w.\-]+)'),
    (m) => 'name@${m[1]}',
  );
  s = s.replaceAllMapped(
    RegExp(
      r'\b([Tt]o|TO|[Ff]rom|FROM|[Bb]y|BY|[Aa]t|AT|[Ff]or|FOR|[Ff]rm|VPA)'
      r"(\s+)([A-Z][\w.'&/]*(?:\s+[A-Z][\w.'&/]*)*)",
    ),
    (m) {
      // Only the leading words up to a bank word (UPI, Ref, A/c...) are a name.
      final words = m[3]!.split(RegExp(r'\s+'));
      final n = words.indexWhere(
        (w) => RegExp(
          r'^(Rs\.?|INR|A/?c|UPI|NEFT|IMPS|RTGS|ATM|POS|Ref|Info|Avl|Bal)\b',
          caseSensitive: false,
        ).hasMatch(w),
      );
      final name = n < 0 ? words.length : n;
      if (name == 0) return m[0]!;
      return '${m[1]}${m[2]}${['NAME', ...words.skip(name)].join(' ')}';
    },
  );
  return s.replaceAll(RegExp(r'\d'), '1');
}

/// A GitHub "Bank message not recognised" issue, filled in.
Uri bankMessageIssueUrl({required String message, String? sender}) =>
    Uri.https('github.com', '/scap3sh4rk/Rivero/issues/new', {
      'template': 'bank_message_format.yml',
      'title': '[Parser] ${sender ?? 'Bank message'}',
      'message': message.length > 1500 ? message.substring(0, 1500) : message,
      'sender': ?sender,
    });
