import 'package:flutter_test/flutter_test.dart';
import 'package:theta_music/core/obsidian.dart';

void main() {
  test('obsidian merge keeps user notes and extra frontmatter', () {
    final first = ObsidianExporter.merge(null, {'type': 'album'}, 'body1\n');
    final edited = '${first.replaceFirst('---\n', '---\nrating: 5\n')}my memo\n';
    final second = ObsidianExporter.merge(edited, {'type': 'album', 'year': '1999'}, 'body2\n');
    expect(second, contains('rating: 5'));
    expect(second, contains('year: 1999'));
    expect(second, contains('my memo'));
    expect(second, contains('body2'));
    expect(second, isNot(contains('body1')));
  });
}
