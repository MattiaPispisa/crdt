import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/widgets/line_number_gutter.dart';

const TextStyle _style = TextStyle(fontFamily: 'monospace', fontSize: 14);

/// The [RenderEditable] under [root] — the render object the gutter reads.
RenderEditable _editableUnder(RenderObject root) {
  RenderEditable? found;
  void visit(RenderObject node) {
    if (found != null) {
      return;
    }
    if (node is RenderEditable) {
      found = node;
      return;
    }
    node.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found!;
}

void main() {
  group('lineStartOffsets', () {
    test('an empty document still has one line', () {
      expect(lineStartOffsets(''), [0]);
    });

    test('a trailing newline opens a last, empty line', () {
      // What every editor shows: 'a\n' is two lines, the second one empty.
      expect(lineStartOffsets('a\n'), [0, 2]);
    });

    test('each offset points just after its newline', () {
      expect(lineStartOffsets('a\nbb\n\nc'), [0, 2, 5, 6]);
    });
  });

  group('lineNumberGutterWidth', () {
    test('grows only when the line count gains a digit', () {
      final small = lineNumberGutterWidth(9, _style);
      expect(lineNumberGutterWidth(1, _style), small);
      expect(lineNumberGutterWidth(99, _style), small);

      final wider = lineNumberGutterWidth(100, _style);
      expect(wider, greaterThan(small));
      expect(lineNumberGutterWidth(999, _style), wider);
      expect(lineNumberGutterWidth(1000, _style), greaterThan(wider));
    });
  });

  group('resolveGutterLines', () {
    /// Pumps a text field of [width] and returns the gutter lines it implies,
    /// measured in the field's own coordinates.
    Future<List<GutterLine>> lines(
      WidgetTester tester,
      String text, {
      double width = 260,
      double height = 300,
      ScrollController? scroll,
    }) async {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: TextField(
                  controller: controller,
                  scrollController: scroll,
                  maxLines: null,
                  expands: true,
                  style: _style,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final editable = _editableUnder(
        tester.renderObject(find.byType(TextField)),
      );
      return resolveGutterLines(
        editable: editable,
        toGutter: Matrix4.identity(),
        height: height,
      );
    }

    testWidgets('a number is drawn on the same line box as its text', (
      tester,
    ) async {
      await lines(tester, 'one\ntwo');
      final editable = _editableUnder(
        tester.renderObject(find.byType(TextField)),
      );
      final number = TextPainter(
        text: TextSpan(
          text: '1',
          style: gutterNumberStyle(editable, _style),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Same box height as a line of the field, so aligning their tops also
      // aligns their baselines. The style handed to the field has no line
      // height of its own — the theme adds it — so measuring with that one
      // draws the number above its text.
      expect(number.height, editable.preferredLineHeight);
      expect(
        TextPainter(
          text: const TextSpan(text: '1', style: _style),
          textDirection: TextDirection.ltr,
        )..layout(),
        isNot(predicate<TextPainter>((p) => p.height == number.height)),
      );
    });

    testWidgets('an empty document shows a single 1', (tester) async {
      expect(await lines(tester, ''), hasLength(1));
      expect((await lines(tester, '')).single.number, 1);
    });

    testWidgets('one number per line, each below the previous', (
      tester,
    ) async {
      final result = await lines(tester, 'one\ntwo\nthree');
      expect(result.map((line) => line.number), [1, 2, 3]);
      expect(result[1].top, greaterThan(result[0].top));
      expect(result[2].top, greaterThan(result[1].top));
    });

    testWidgets('a wrapped line still gets exactly one number', (
      tester,
    ) async {
      // The first line is far too long for the pane, so it wraps over several
      // visual rows. Its number must not repeat, and the next one has to skip
      // past every row the wrap took.
      final wrapped = await lines(tester, '${'word ' * 20}\nsecond');
      final plain = await lines(tester, 'short\nsecond');

      expect(wrapped.map((line) => line.number), [1, 2]);
      final rowHeight = plain[1].top - plain[0].top;
      expect(wrapped[1].top - wrapped[0].top, greaterThan(rowHeight * 2));
    });

    testWidgets('scrolling carries the numbers with the text', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      final text = List.generate(200, (i) => 'line $i').join('\n');
      final before = await lines(tester, text, scroll: scroll);
      expect(before.first.number, 1);

      scroll.jumpTo(400);
      await tester.pump();
      final after = await lines(tester, text, scroll: scroll);

      // The top of the gutter now shows a line from further down, and nothing
      // above the viewport is returned.
      expect(after.first.number, greaterThan(1));
      expect(after.first.top, greaterThanOrEqualTo(-_style.fontSize!));
    });
  });
}
