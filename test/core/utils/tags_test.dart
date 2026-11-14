import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/utils/tags.dart';

void main() {
  test('tags are #words in a note, lowercase, without repeats', () {
    expect(tagsIn('Dinner #Goa with #office-team, #goa again'), [
      'goa',
      'office-team',
    ]);
    expect(tagsIn('no tags, just ₹500 # alone'), isEmpty);
    expect(tagsIn(null), isEmpty);
  });
}
