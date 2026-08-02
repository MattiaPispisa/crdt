import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/export/pdf_export.dart';

void main() {
  // The exporter loads its fonts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('markdownToPdfBytes', () {
    test('renders every construct the welcome document uses', () async {
      // kPlaceholderMarkdown is the app's own showcase: headings, emphasis,
      // inline and fenced code, nested lists, a quote, a table, a rule, a
      // link and an image. If the walk misses a tag, it throws here.
      final bytes = await markdownToPdfBytes(
        kPlaceholderMarkdown,
        title: 'Welcome',
      );

      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('keeps accented text, which the built-in PDF fonts would drop', () {
      // Embedding Roboto is the whole reason the fonts are bundled; a plain
      // WinAnsi font would turn these into '?'.
      expect(
        markdownToPdfBytes('Perché è così: naïve, façon.', title: 'Accents'),
        completes,
      );
    });

    test('an empty document still produces a valid file', () async {
      final bytes = await markdownToPdfBytes('', title: 'Empty');
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
