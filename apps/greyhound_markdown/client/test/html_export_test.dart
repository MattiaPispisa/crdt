import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/services/export/html_export.dart';

void main() {
  group('markdownToHtmlDocument', () {
    test('wraps the rendered markdown in a standalone page', () {
      final html = markdownToHtmlDocument('# Hi', title: 'Notes');

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<meta charset="utf-8">'));
      expect(html, contains('<title>Notes</title>'));
      // The style sheet is inline, so the file opens with no network.
      expect(html, contains('<style>'));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('<script')));
    });

    test('renders the GitHub constructs the preview shows', () {
      final html = markdownToHtmlDocument('''
# Title

Some **bold**, *italic* and ~~struck~~ text.

- one
- two

| a | b |
| - | - |
| 1 | 2 |

```dart
void main() {}
```
''', title: 'Doc');

      expect(html, contains('<h1>Title</h1>'));
      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains('<del>struck</del>'));
      expect(html, contains('<li>one</li>'));
      expect(html, contains('<table>'));
      expect(html, contains('<code class="language-dart">'));
    });

    test('escapes markup coming from the document and from the title', () {
      final html = markdownToHtmlDocument(
        'a < b & c',
        title: '<script>x</script>',
      );

      expect(html, contains('a &lt; b &amp; c'));
      expect(html, contains('<title>&lt;script&gt;x&lt;/script&gt;</title>'));
    });
  });
}
