/// The cards that can sit on Home under Safe to spend. The user picks which
/// and in what order (Settings > Home screen); stored as names.
enum HomeWidget {
  plan('Plan', 'What is left to spend from the salary plan'),
  owed('Owed to you', 'What friends owe you'),
  autopay('Next autopay', 'The next SIP, subscription or bill'),
  spent('Spent this cycle', 'Everyday spending since payday'),
  goals('Goals', 'Progress of the goals due soonest', wide: true),
  netWorth('Net worth', 'Accounts you count in it, minus what you owe'),
  cardBills('Card bills', 'What cards owe and the next due date'),
  youOwe('You owe', 'What you borrowed from people');

  HomeWidget(this.label, this.description, {this.wide = false});

  final String label;
  final String description;

  /// Takes the full width (the rest sit two to a row).
  final bool wide;

  static const List<HomeWidget> defaults = [plan, owed, autopay, spent, goals];

  /// The saved names as widgets, in order (unknown names are skipped).
  static List<HomeWidget> chosen(List<String>? names) => names == null
      ? defaults
      : [
          for (final n in names)
            ?HomeWidget.values.where((w) => w.name == n).firstOrNull,
        ];
}
