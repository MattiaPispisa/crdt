import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/widgets/code_element_builder.dart';
import 'package:highlight/languages/all.dart';

void main() {
  group('resolveHighlightLanguage', () {
    test('maps common aliases to canonical grammars', () {
      expect(resolveHighlightLanguage('ts'), 'typescript');
      expect(resolveHighlightLanguage('js'), 'javascript');
      expect(resolveHighlightLanguage('py'), 'python');
      expect(resolveHighlightLanguage('sh'), 'bash');
      expect(resolveHighlightLanguage('html'), 'xml');
      expect(resolveHighlightLanguage('c#'), 'cs');
      expect(resolveHighlightLanguage('golang'), 'go');
    });

    test('passes through a canonical name and is case-insensitive', () {
      expect(resolveHighlightLanguage('dart'), 'dart');
      expect(resolveHighlightLanguage('Dart'), 'dart');
      expect(resolveHighlightLanguage('TS'), 'typescript');
    });

    test('returns null for an unknown language', () {
      expect(resolveHighlightLanguage('not-a-language'), isNull);
      expect(resolveHighlightLanguage(''), isNull);
    });

    test('every alias resolves to a registered grammar', () {
      for (final canonical in kLanguageAliases.values) {
        expect(allLanguages.containsKey(canonical), isTrue,
            reason: '"$canonical" is not a registered grammar');
      }
    });
  });
}
