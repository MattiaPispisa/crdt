import 'dart:convert';
import 'dart:typed_data';

import 'package:greyhound_markdown_client/src/services/export/html_export.dart';
import 'package:greyhound_markdown_client/src/services/export/pdf_export.dart';
import 'package:greyhound_markdown_client/src/services/file_saver/file_saver.dart';

/// A file type the document can be exported as.
enum ExportFormat {
  /// The markdown source, byte for byte.
  markdown('Markdown', 'md', 'text/markdown'),

  /// A standalone styled web page.
  html('HTML', 'html', 'text/html'),

  /// A paginated A4 document.
  pdf('PDF', 'pdf', 'application/pdf');

  const ExportFormat(this.label, this.extension, this.mimeType);

  /// Name shown in the export menu.
  final String label;

  /// File extension, without the dot.
  final String extension;

  /// Media type the file is saved with.
  final String mimeType;
}

/// Exports the room's markdown as a file the user can keep.
///
/// The rendering of each format lives in its own file under `export/`; this
/// class only picks one and hands the bytes to a [FileSaver].
class DocumentExporter {
  /// Creates an exporter.
  ///
  /// [saver] defaults to the platform one; tests pass their own to stay off
  /// the disk.
  DocumentExporter({FileSaver? saver})
    : _saver = saver ?? FileSaver.forPlatform();

  final FileSaver _saver;

  /// Renders [markdown] as [format] and saves it under [fileName] (without
  /// the extension, which [format] adds).
  ///
  /// Returns `false` when the user closed the save dialog without choosing a
  /// destination.
  Future<bool> export({
    required String markdown,
    required ExportFormat format,
    required String fileName,
  }) async {
    final bytes = switch (format) {
      ExportFormat.markdown => utf8.encode(markdown),
      ExportFormat.html => utf8.encode(
        markdownToHtmlDocument(markdown, title: fileName),
      ),
      ExportFormat.pdf => await markdownToPdfBytes(markdown, title: fileName),
    };
    return _saver.save(
      fileName: '$fileName.${format.extension}',
      bytes: Uint8List.fromList(bytes),
      mimeType: format.mimeType,
    );
  }
}

/// The file name to offer for [markdown]: its first heading slugified, or
/// [fallback] when it opens with something else.
String suggestedFileName(String markdown, {required String fallback}) =>
    fileNameOf(documentTitle(markdown) ?? fallback, fallback: fallback);

/// The document's title: the text of its first ATX heading, or `null` when it
/// opens with something else.
///
/// Read straight off the source rather than from the parsed tree — a title is
/// a line, and this runs on every export.
String? documentTitle(String markdown) {
  for (final line in const LineSplitter().convert(markdown)) {
    final match = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$').firstMatch(line);
    if (match != null) {
      final title = match.group(1)!.trim();
      if (title.isNotEmpty) {
        return title;
      }
    }
  }
  return null;
}

/// [title] as a file name: lowercase words joined by dashes, at most 60
/// characters. Falls back to [fallback] when nothing usable is left.
String fileNameOf(String title, {required String fallback}) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  if (slug.isEmpty) {
    return fallback;
  }
  return slug.length <= 60
      ? slug
      : slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
}
