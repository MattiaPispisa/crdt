// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

final _peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

const _color = Color(0xFFAA0000);

void main() {
  late CRDTDocument document;
  late CRDTFugueRichTextHandler page;
  late QuillController controller;

  setUp(() {
    document = CRDTDocument(peerId: _peerA);
    page = CRDTFugueRichTextHandler(document, 'page');
    controller = QuillController.basic();
    addTearDown(controller.dispose);
  });

  tearDown(() => document.dispose());

  CrdtTextCursor cursor(int base, [int? extent]) => CrdtTextCursor(
    id: 'bob',
    color: _color,
    base: page.stablePositionAt(base),
    extent: extent == null ? null : page.stablePositionAt(extent),
  );

  Widget editor(
    QuillController controller,
    List<CrdtTextCursor> cursors, {
    EdgeInsets padding = EdgeInsets.zero,
    String? placeholder,
    FocusNode? focusNode,
    CrdtTextCursorLabelPlacement labelPlacement =
        CrdtTextCursorLabelPlacement.auto,
    void Function(FugueElementID?, FugueElementID?)? onAnchors,
  }) => CrdtQuillBinder(
    id: 'page',
    controller: controller,
    onSelectionAnchorsChanged: onAnchors,
    child: CrdtQuillCursorsOverlay(
      id: 'page',
      cursors: cursors,
      labelPlacement: labelPlacement,
      motionDuration: Duration.zero,
      child: QuillEditor.basic(
        controller: controller,
        focusNode: focusNode,
        config: QuillEditorConfig(
          padding: padding,
          placeholder: placeholder,
          unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
        ),
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester,
    List<CrdtTextCursor> cursors, {
    double height = 400,
    EdgeInsets padding = EdgeInsets.zero,
    String? placeholder,
  }) async {
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: height,
                child: editor(
                  controller,
                  cursors,
                  padding: padding,
                  placeholder: placeholder,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder overlayPaint() => find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_TextCursorsPainter',
  );

  RenderEditor renderEditor(WidgetTester tester) =>
      tester.allRenderObjects.whereType<RenderEditor>().first;

  // Maps a rect local to the editor into the overlay.
  Rect mapped(WidgetTester tester, Rect rect) {
    final overlay = tester.renderObject(
      find.byType(CrdtTextCursorsOverlay).first,
    );
    return MatrixUtils.transformRect(
      renderEditor(tester).getTransformTo(overlay),
      rect,
    );
  }

  // The caret the overlay paints for [offset], on an editor without padding:
  // there Quill's caret rect is the right one.
  Rect caret(WidgetTester tester, int offset) {
    final rect = mapped(
      tester,
      renderEditor(tester).getLocalRectForCaret(TextPosition(offset: offset)),
    );
    return Rect.fromLTWH(rect.left, rect.top, 2, rect.height);
  }

  testWidgets('two peers see each other, through a concurrent delete', (
    tester,
  ) async {
    final bob = CRDTDocument(peerId: _peerB);
    addTearDown(bob.dispose);
    final bobPage = CRDTFugueRichTextHandler(bob, 'page');
    final bobController = QuillController.basic();
    addTearDown(bobController.dispose);
    final bobFocus = FocusNode();
    addTearDown(bobFocus.dispose);
    page.insert(0, 'hello world');
    bob.importChanges(document.exportChanges());

    var cursors = <CrdtTextCursor>[];
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Row(
                children: [
                  Expanded(
                    child: CrdtProvider.value(
                      value: document,
                      child: editor(controller, cursors),
                    ),
                  ),
                  Expanded(
                    child: CrdtProvider.value(
                      value: bob,
                      child: editor(
                        bobController,
                        const [],
                        focusNode: bobFocus,
                        onAnchors: (base, extent) {
                          // As a presence channel: after the frame.
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => rebuild(
                              () => cursors = [
                                if (base != null && extent != null)
                                  CrdtTextCursor(
                                    id: 'bob',
                                    color: _color,
                                    base: base,
                                    extent: extent,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    bobFocus.requestFocus();
    await tester.pump();

    bobController.updateSelection(
      const TextSelection(baseOffset: 6, extentOffset: 9),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.pump();

    Rect highlight(int from, int to) {
      final left = caret(tester, from);
      return Rect.fromLTRB(
        left.left,
        left.top,
        caret(tester, to).left,
        left.bottom,
      );
    }

    expect(
      overlayPaint().first,
      paints
        ..rect(rect: highlight(6, 9))
        ..rect(rect: caret(tester, 9), color: _color),
    );

    // Alice inserts before the cursor, on her own editor.
    page.insert(0, 'XX ');
    await tester.pump();
    expect(
      overlayPaint().first,
      paints
        ..rect(rect: highlight(9, 12))
        ..rect(rect: caret(tester, 12), color: _color),
    );

    // Alice deletes the end of the selection while Bob writes elsewhere.
    page.delete(10, 4);
    bobPage.insert(0, 'B');
    document.importChanges(bob.exportChanges());
    bob.importChanges(document.exportChanges());
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(page.text, 'XX Bhello w');
    expect(bobPage.text, page.text);
    expect(tester.takeException(), isNull);
    expect(
      overlayPaint().first,
      paints
        ..rect()
        ..rect(rect: caret(tester, 11), color: _color),
    );

    // On the web, a change of the focused editor starts a 500 ms caret timer.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('a caret past an emoji and an embed', (tester) async {
    page
      ..insert(0, 'a😀b')
      ..insertEmbed(3, {'type': 'image', 'source': 'x.png'})
      ..insert(4, 'cd');
    await mount(tester, [cursor(5)]);

    // `a`, two code units, `b`, the embed, `c`.
    expect(controller.document.toPlainText()[4], '￼');
    expect(overlayPaint(), paints..rect(rect: caret(tester, 6), color: _color));
  });

  testWidgets('a selection paints each visual line of each block', (
    tester,
  ) async {
    const long = 'aaaa bbbb cccc dddd eeee ffff gggg hhhh';
    page.insert(0, '$long\n\nend');
    await mount(tester, [cursor(2, page.length)]);

    // Three visual lines, the empty line, then `end`.
    final editor = renderEditor(tester);
    final second = editor.getLineAtOffset(const TextPosition(offset: 20));
    expect(second.start, greaterThan(0));
    final lastLine = caret(tester, long.length + 2);
    expect(
      overlayPaint(),
      paints
        ..rect(
          rect: Rect.fromLTRB(
            caret(tester, 2).left,
            caret(tester, 2).top,
            mapped(
              tester,
              editor.getLocalRectForCaret(
                TextPosition(
                  offset: second.start,
                  affinity: TextAffinity.upstream,
                ),
              ),
            ).left,
            caret(tester, 2).bottom,
          ),
        )
        ..rect(
          rect: Rect.fromLTRB(
            caret(tester, second.start).left,
            caret(tester, second.start).top,
            mapped(
              tester,
              editor.getLocalRectForCaret(
                TextPosition(
                  offset: second.end,
                  affinity: TextAffinity.upstream,
                ),
              ),
            ).left,
            caret(tester, second.start).bottom,
          ),
        )
        ..rect()
        ..rect(
          rect: Rect.fromLTRB(
            lastLine.left,
            lastLine.top,
            caret(tester, long.length + 5).left,
            lastLine.bottom,
          ),
        )
        ..rect(rect: caret(tester, long.length + 5), color: _color),
    );
    expect(
      overlayPaint(),
      isNot(
        paints
          ..rect()
          ..rect()
          ..rect()
          ..rect()
          ..rect()
          ..rect(),
      ),
    );
  });

  testWidgets('a scroll moves the carets with the editor', (tester) async {
    page.insert(0, List.generate(40, (i) => 'line $i').join('\n'));
    await mount(tester, [cursor(16)], height: 100);
    final before = caret(tester, 16);

    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(QuillEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(10);
    await tester.pump();

    final after = before.shift(const Offset(0, -10));
    expect(caret(tester, 16), after);
    expect(overlayPaint(), paints..rect(rect: after, color: _color));
  });

  testWidgets('a caret and a selection keep the padding of the editor', (
    tester,
  ) async {
    page.insert(0, 'hello');
    const padding = EdgeInsets.fromLTRB(20, 10, 5, 5);
    await mount(tester, [cursor(0, 2)], padding: padding);

    final start = renderEditor(
      tester,
    ).getLocalRectForCaret(const TextPosition(offset: 0));
    final end = renderEditor(
      tester,
    ).getLocalRectForCaret(const TextPosition(offset: 2));
    // Without the padding here: Quill's caret rect leaves it out.
    expect(start.left, lessThan(20));
    expect(
      overlayPaint(),
      paints
        ..rect(
          rect: Rect.fromLTRB(
            start.left + 20,
            start.top,
            end.left + 20,
            start.bottom,
          ),
        )
        ..rect(
          rect: Rect.fromLTWH(end.left + 20, end.top, 2, end.height),
          color: _color,
        ),
    );
  });

  for (final stored in [false, true]) {
    testWidgets('an anchor at the end of a document, last newline '
        '${stored ? 'stored' : 'free'}', (tester) async {
      page.insert(0, 'hello');
      if (stored) {
        page.insert(5, '\n', attributes: {'header': 1});
      }
      await mount(tester, [cursor(2, page.length)]);

      final last = controller.document.length - 1;
      expect(tester.takeException(), isNull);
      expect(
        overlayPaint(),
        paints
          ..rect()
          ..rect(rect: caret(tester, last), color: _color),
      );
    });
  }

  testWidgets('a caret on an empty document with a placeholder', (
    tester,
  ) async {
    await mount(tester, [
      CrdtTextCursor(id: 'bob', color: _color, base: FugueElementID.nullID()),
    ], placeholder: 'write here');

    expect(tester.takeException(), isNull);
    expect(overlayPaint(), paints..rect(rect: caret(tester, 0), color: _color));
  });

  testWidgets('passes its look to the overlay', (tester) async {
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: const MaterialApp(
          home: CrdtQuillCursorsOverlay(
            id: 'page',
            cursors: [],
            labelPlacement: CrdtTextCursorLabelPlacement.below,
            child: SizedBox(),
          ),
        ),
      ),
    );

    final overlay = tester.widget<CrdtTextCursorsOverlay>(
      find.byType(CrdtTextCursorsOverlay),
    );
    expect(overlay.labelPlacement, CrdtTextCursorLabelPlacement.below);
    expect(
      overlay.motionDuration,
      CrdtTextCursorsOverlay.defaultMotionDuration,
    );
  });
}
