import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/services/export/document_export.dart';

import 'helpers/recording_file_saver.dart';

void main() {
  // The PDF format loads its fonts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('documentTitle', () {
    test('takes the first heading, at any level', () {
      expect(documentTitle('## Release notes\n\n# Later'), 'Release notes');
      expect(documentTitle('  ### Indented'), 'Indented');
      expect(documentTitle('# Closed ###'), 'Closed');
    });

    test('is null when the document opens with something else', () {
      expect(documentTitle('just a paragraph'), isNull);
      expect(documentTitle('#no space is not a heading'), isNull);
      expect(documentTitle(''), isNull);
    });
  });

  group('fileNameOf', () {
    test('slugifies the title', () {
      expect(fileNameOf('Release Notes!', fallback: 'doc'), 'release-notes');
      expect(fileNameOf('  Ada & Co.  ', fallback: 'doc'), 'ada-co');
    });

    test('falls back when nothing usable is left', () {
      expect(fileNameOf('###', fallback: 'room-42'), 'room-42');
    });

    test('never runs past 60 characters, nor ends on a dash', () {
      final name = fileNameOf('word ' * 40, fallback: 'doc');
      expect(name.length, lessThanOrEqualTo(60));
      expect(name, isNot(endsWith('-')));
    });
  });

  group('suggestedFileName', () {
    test('slugifies the first heading, or falls back to the room', () {
      expect(
        suggestedFileName('# Release Notes\n\nx', fallback: 'greyhound-42'),
        'release-notes',
      );
      expect(
        suggestedFileName('no heading', fallback: 'greyhound-42'),
        'greyhound-42',
      );
    });
  });

  group('DocumentExporter', () {
    test('saves the markdown source unchanged', () async {
      final saver = RecordingFileSaver();
      final saved = await DocumentExporter(saver: saver).export(
        markdown: '# Notes\n\nHello 🌍 caffè',
        format: ExportFormat.markdown,
        fileName: 'notes',
      );

      expect(saved, isTrue);
      expect(saver.fileName, 'notes.md');
      expect(saver.mimeType, 'text/markdown');
      expect(utf8.decode(saver.bytes!), '# Notes\n\nHello 🌍 caffè');
    });

    test('titles the HTML page with the file name', () async {
      final saver = RecordingFileSaver();
      await DocumentExporter(saver: saver).export(
        markdown: 'no heading here',
        format: ExportFormat.html,
        fileName: 'greyhound-42',
      );

      expect(saver.fileName, 'greyhound-42.html');
      expect(saver.mimeType, 'text/html');
      expect(utf8.decode(saver.bytes!), contains('<title>greyhound-42</title>'));
    });

    test('renders a PDF for the pdf format', () async {
      final saver = RecordingFileSaver();
      await DocumentExporter(saver: saver).export(
        markdown: '# Notes',
        format: ExportFormat.pdf,
        fileName: 'notes',
      );

      expect(saver.fileName, 'notes.pdf');
      expect(saver.mimeType, 'application/pdf');
      expect(utf8.decode(saver.bytes!.sublist(0, 5)), '%PDF-');
    });

    test('reports a save dialog the user closed', () async {
      final saver = RecordingFileSaver()..cancel = true;
      final saved = await DocumentExporter(saver: saver).export(
        markdown: '# Notes',
        format: ExportFormat.markdown,
        fileName: 'notes',
      );

      expect(saved, isFalse);
      expect(saver.saves, 0);
    });
  });
}
