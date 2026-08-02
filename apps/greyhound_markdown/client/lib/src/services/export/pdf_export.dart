import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:greyhound_markdown_client/src/config.dart';

/// Renders [markdown] as an A4 PDF titled [title].
///
/// The markdown is parsed with [kMarkdownExtensionSet] — the dialect of the
/// preview — and the resulting tree is mapped onto PDF widgets. Two things do
/// not survive the trip and come out as their alt text: **images** (fetching
/// them would need the network, and CORS on the web) and **emoji** (no emoji
/// font is embedded).
Future<Uint8List> markdownToPdfBytes(
  String markdown, {
  required String title,
}) async {
  final fonts = await _loadFonts();
  final nodes = md.Document(extensionSet: kMarkdownExtensionSet).parse(markdown);
  final document = pw.Document(title: title)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 56),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.italic,
          boldItalic: fonts.boldItalic,
        ),
        build: (context) => _Renderer(fonts).blocks(nodes),
      ),
    );
  return document.save();
}

/// The typefaces a rendered document uses.
class _Fonts {
  const _Fonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.mono,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final pw.Font mono;
}

/// The loaded fonts, kept after the first export: parsing four TTFs takes long
/// enough to be worth doing once.
_Fonts? _fonts;

/// Loads the embedded Roboto family (Courier, a built-in PDF font, covers
/// code).
///
/// Roboto is embedded rather than using the built-in text fonts because those
/// only cover WinAnsi: accented and non-Latin characters would be dropped.
Future<_Fonts> _loadFonts() async {
  if (_fonts != null) {
    return _fonts!;
  }
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return _fonts = _Fonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
    italic: await load('Roboto-Italic'),
    boldItalic: await load('Roboto-BoldItalic'),
    mono: pw.Font.courier(),
  );
}

/// Forgets the cached fonts. Only tests need this.
void debugResetPdfFonts() => _fonts = null;

/// The markdown tags that open a block of their own. Anything else found
/// between blocks is inline content and gets wrapped in a paragraph.
const Set<String> _kBlockTags = {
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
  'p', 'pre', 'blockquote', 'ul', 'ol', 'hr', 'table', 'section',
};

/// Body text size; everything else is derived from it.
const double _kFontSize = 11;

const PdfColor _kTextColor = PdfColor.fromInt(0xFF1A1C1E);
const PdfColor _kMutedColor = PdfColor.fromInt(0xFF5F6368);
const PdfColor _kLinkColor = PdfColor.fromInt(0xFF00695C);
const PdfColor _kRuleColor = PdfColor.fromInt(0xFFD7DBDF);
const PdfColor _kCodeBackground = PdfColor.fromInt(0xFFF4F6F8);

/// Turns a parsed markdown tree into PDF widgets.
///
/// Blocks become widgets, inline content becomes one span tree per block. An
/// unknown tag is not dropped: its children are rendered in its place, so a
/// construct this app does not style still shows its text.
class _Renderer {
  _Renderer(this.fonts);

  final _Fonts fonts;

  /// The widgets for a run of sibling nodes.
  List<pw.Widget> blocks(List<md.Node> nodes) {
    final widgets = <pw.Widget>[];
    final loose = <md.Node>[];

    void flush() {
      if (loose.isEmpty) {
        return;
      }
      widgets.add(_paragraph(loose.toList()));
      loose.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _kBlockTags.contains(node.tag)) {
        flush();
        widgets.add(_block(node));
      } else if (loose.isEmpty && node.textContent.trim().isEmpty) {
        // The blank lines between two blocks: they would otherwise open an
        // empty paragraph.
        continue;
      } else {
        loose.add(node);
      }
    }
    flush();
    return widgets;
  }

  pw.Widget _block(md.Element element) {
    switch (element.tag) {
      case 'h1':
        return _heading(element, 1.9, 20);
      case 'h2':
        return _heading(element, 1.5, 18);
      case 'h3':
        return _heading(element, 1.25, 16);
      case 'h4':
        return _heading(element, 1.1, 14);
      case 'h5':
      case 'h6':
        return _heading(element, 1, 12);
      case 'p':
        return _paragraph(element.children ?? const []);
      case 'pre':
        return _codeBlock(element);
      case 'blockquote':
        return _quote(element);
      case 'ul':
        return _list(element, ordered: false);
      case 'ol':
        return _list(element, ordered: true);
      case 'hr':
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 12),
          height: 0.7,
          color: _kRuleColor,
        );
      case 'table':
        return _table(element);
      default:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: blocks(element.children ?? const []),
        );
    }
  }

  pw.Widget _heading(md.Element element, double scale, double topSpace) {
    return pw.Container(
      margin: pw.EdgeInsets.only(top: topSpace, bottom: 6),
      child: pw.RichText(
        text: _span(
          element.children ?? const [],
          _baseStyle.copyWith(
            fontSize: _kFontSize * scale,
            font: fonts.bold,
            fontWeight: pw.FontWeight.bold,
            lineSpacing: 2,
          ),
        ),
      ),
    );
  }

  pw.Widget _paragraph(List<md.Node> nodes) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.RichText(text: _span(nodes, _baseStyle)),
    );
  }

  /// A fenced or indented code block. The `pre` wraps a single `code` whose
  /// text the parser already escaped for HTML, so it is unescaped here.
  pw.Widget _codeBlock(md.Element element) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(color: _kCodeBackground),
      child: pw.Text(
        _unescape(element.textContent).trimRight(),
        style: _baseStyle.copyWith(
          font: fonts.mono,
          fontSize: _kFontSize * 0.85,
          lineSpacing: 1.5,
        ),
      ),
    );
  }

  pw.Widget _quote(md.Element element) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(left: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: _kRuleColor, width: 3),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: blocks(element.children ?? const []),
      ),
    );
  }

  /// A bullet or numbered list. Nested lists arrive as another list inside an
  /// item, so they indent by going through [blocks] again.
  pw.Widget _list(md.Element element, {required bool ordered}) {
    final items = (element.children ?? const [])
        .whereType<md.Element>()
        .where((child) => child.tag == 'li')
        .toList();
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 22,
                child: pw.Text(
                  ordered ? '${start + i}.' : '•',
                  style: _baseStyle,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: blocks(items[i].children ?? const []),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _table(md.Element element) {
    final rows = <pw.TableRow>[];
    for (final section in (element.children ?? const []).whereType<md.Element>()) {
      final header = section.tag == 'thead';
      for (final row in (section.children ?? const []).whereType<md.Element>()) {
        if (row.tag != 'tr') {
          continue;
        }
        rows.add(
          pw.TableRow(
            decoration: header
                ? const pw.BoxDecoration(color: _kCodeBackground)
                : null,
            children: [
              for (final cell
                  in (row.children ?? const []).whereType<md.Element>())
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  alignment: _cellAlignment(cell),
                  child: pw.RichText(
                    textAlign: _cellTextAlign(cell),
                    text: _span(
                      cell.children ?? const [],
                      header
                          ? _baseStyle.copyWith(
                              font: fonts.bold,
                              fontWeight: pw.FontWeight.bold,
                            )
                          : _baseStyle,
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Table(
        border: pw.TableBorder.all(color: _kRuleColor, width: 0.7),
        children: rows,
      ),
    );
  }

  /// The span tree of a run of inline nodes, each style layered on [parent].
  pw.TextSpan _span(List<md.Node> nodes, pw.TextStyle parent) {
    return pw.TextSpan(
      style: parent,
      children: [
        for (final node in nodes) _inline(node, parent),
      ],
    );
  }

  pw.InlineSpan _inline(md.Node node, pw.TextStyle parent) {
    if (node is md.Text) {
      return pw.TextSpan(text: _unescape(node.text), style: parent);
    }
    if (node is! md.Element) {
      return pw.TextSpan(text: node.textContent, style: parent);
    }
    switch (node.tag) {
      case 'strong':
        return _span(
          node.children ?? const [],
          parent.copyWith(
            font: parent.fontStyle == pw.FontStyle.italic
                ? fonts.boldItalic
                : fonts.bold,
            fontWeight: pw.FontWeight.bold,
          ),
        );
      case 'em':
        return _span(
          node.children ?? const [],
          parent.copyWith(
            font: parent.fontWeight == pw.FontWeight.bold
                ? fonts.boldItalic
                : fonts.italic,
            fontStyle: pw.FontStyle.italic,
          ),
        );
      case 'del':
        return _span(
          node.children ?? const [],
          parent.copyWith(decoration: pw.TextDecoration.lineThrough),
        );
      case 'code':
        return pw.TextSpan(
          text: _unescape(node.textContent),
          style: parent.copyWith(
            font: fonts.mono,
            fontSize: (parent.fontSize ?? _kFontSize) * 0.9,
            background: const pw.BoxDecoration(color: _kCodeBackground),
          ),
        );
      case 'a':
        final href = node.attributes['href'];
        return pw.TextSpan(
          style: parent.copyWith(
            color: _kLinkColor,
            decoration: pw.TextDecoration.underline,
          ),
          annotation: href == null ? null : pw.AnnotationUrl(href),
          children: [
            for (final child in node.children ?? const <md.Node>[])
              _inline(child, parent.copyWith(color: _kLinkColor)),
          ],
        );
      case 'br':
        return pw.TextSpan(text: '\n', style: parent);
      case 'img':
        // Images are not embedded: fetching them needs the network, and CORS
        // on the web. The alt text keeps the meaning of the line.
        final alt = node.attributes['alt'];
        final label = alt == null || alt.isEmpty
            ? node.attributes['src'] ?? 'image'
            : alt;
        return pw.TextSpan(
          text: '[$label]',
          style: parent.copyWith(
            color: _kMutedColor,
            font: fonts.italic,
            fontStyle: pw.FontStyle.italic,
          ),
        );
      case 'input':
        // The checkbox of a task-list item.
        final checked = node.attributes.containsKey('checked');
        return pw.TextSpan(text: checked ? '[x] ' : '[ ] ', style: parent);
      default:
        return _span(node.children ?? const [], parent);
    }
  }

  pw.TextStyle get _baseStyle => pw.TextStyle(
    font: fonts.regular,
    fontNormal: fonts.regular,
    fontBold: fonts.bold,
    fontItalic: fonts.italic,
    fontBoldItalic: fonts.boldItalic,
    fontSize: _kFontSize,
    color: _kTextColor,
    lineSpacing: 2.5,
  );
}

pw.Alignment _cellAlignment(md.Element cell) {
  final style = cell.attributes['style'] ?? '';
  if (style.contains('right')) {
    return pw.Alignment.centerRight;
  }
  if (style.contains('center')) {
    return pw.Alignment.center;
  }
  return pw.Alignment.centerLeft;
}

pw.TextAlign _cellTextAlign(md.Element cell) {
  final style = cell.attributes['style'] ?? '';
  if (style.contains('right')) {
    return pw.TextAlign.right;
  }
  if (style.contains('center')) {
    return pw.TextAlign.center;
  }
  return pw.TextAlign.left;
}

/// Undoes the HTML escaping the markdown parser applies to code blocks and to
/// escaped characters. `&amp;` goes last, so `&amp;lt;` stays `&lt;`.
String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
