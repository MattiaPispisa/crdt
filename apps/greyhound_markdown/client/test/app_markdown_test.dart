import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/app_markdown.dart';

Future<void> _pump(WidgetTester tester, String data) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: AppMarkdown(data: data))),
  );
}

void main() {
  testWidgets('headings form a ramp, and each one binds to the text under it', (
    tester,
  ) async {
    await _pump(tester, 'hello');
    final sheet = tester.widget<Markdown>(find.byType(Markdown)).styleSheet!;

    final headings = <(TextStyle, EdgeInsets)>[
      (sheet.h1!, sheet.h1Padding!),
      (sheet.h2!, sheet.h2Padding!),
      (sheet.h3!, sheet.h3Padding!),
      (sheet.h4!, sheet.h4Padding!),
      (sheet.h5!, sheet.h5Padding!),
      (sheet.h6!, sheet.h6Padding!),
    ];

    for (var i = 0; i < headings.length; i++) {
      final (style, padding) = headings[i];
      // The gap above carries the separation the reader sees; the gap below
      // has to stay smaller or the heading floats between two sections.
      expect(padding.top, greaterThan(padding.bottom),
          reason: 'h${i + 1} is not bound to the text under it');
      if (i == 0) {
        continue;
      }
      // Mapping levels onto textTheme roles silently broke this: titleSmall is
      // 14 and bodyLarge is 16, so an h5 came out bigger than an h4.
      final (previous, previousPadding) = headings[i - 1];
      expect(style.fontSize, lessThan(previous.fontSize!),
          reason: 'h${i + 1} is not smaller than h$i');
      expect(padding.top, lessThan(previousPadding.top),
          reason: 'h${i + 1} does not separate less than h$i');
    }
  });

  testWidgets('highlights a fence whose language the highlighter knows', (
    tester,
  ) async {
    await _pump(tester, '```dart\nvoid main() {}\n```');

    final view = tester.widget<HighlightView>(find.byType(HighlightView));
    expect(view.language, 'dart');
  });

  testWidgets('renders a fence in an unknown language as plain code', (
    tester,
  ) async {
    await _pump(tester, '```not-a-language\nkey = "value"\n```');

    expect(find.byType(HighlightView), findsNothing);
    expect(find.textContaining('key = "value"'), findsOneWidget);
  });

  testWidgets('uses the same markdown flavour as the exporters', (
    tester,
  ) async {
    await _pump(tester, 'hello');

    final markdown = tester.widget<Markdown>(find.byType(Markdown));
    expect(markdown.extensionSet, same(kMarkdownExtensionSet));
  });
}
