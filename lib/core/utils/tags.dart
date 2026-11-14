/// Tags are plain #words in an entry's note ("Dinner #goa #office"), so they
/// need no extra storage and survive export and backup as they are.
final _tag = RegExp(r'#([\p{L}\p{N}_-]+)', unicode: true);

/// The tags in [note], lowercase, in order, without repeats.
List<String> tagsIn(String? note) => note == null
    ? const []
    : {for (final m in _tag.allMatches(note)) m[1]!.toLowerCase()}.toList();
