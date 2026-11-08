// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder extends EmbedBuilder {
  _Recorder(this.key);

  @override
  final String key;

  final List<EmbedContext> contexts = [];

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '[$key ${node.value.data}]';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    contexts.add(embedContext);
    return Text('$key ${embedContext.node.value.data}');
  }
}

QuillController _controller(Object embed, [Map<String, dynamic>? style]) {
  final controller = QuillController(
    document: Document.fromDelta(
      Delta()
        ..insert('a')
        ..insert({crdtQuillEmbedType: embed}, style)
        ..insert('\n'),
    ),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _show(
  WidgetTester tester,
  QuillController controller,
  List<EmbedBuilder> builders,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: QuillEditor.basic(
        controller: controller,
        config: QuillEditorConfig(embedBuilders: builders),
      ),
    ),
  ),
);

void main() {
  testWidgets('a wrapped embed is built by the builder of its first key '
      'that has one', (tester) async {
    final video = _Recorder('video');
    final image = _Recorder('image');
    final builders = crdtQuillEmbedBuilders([video, image]);
    final controller = _controller(
      {'alt': 'A cat', 'image': 'a.png', 'video': 'v.mp4'},
      {'bold': true},
    );
    await _show(tester, controller, builders);

    expect(tester.takeException(), isNull);
    expect(find.text('image a.png', findRichText: true), findsOneWidget);
    expect(video.contexts, isEmpty);
    final context = image.contexts.single;
    expect(context.node.value.type, 'image');
    expect(context.node.style.attributes, {'bold': Attribute.bold});
    expect(context.controller, same(controller));
    expect(context.readOnly, isTrue);
    expect(context.inline, isTrue);
    expect(context.textStyle, isNotNull);
    expect(controller.document.toPlainText(builders), 'a[image a.png]\n');
  });

  testWidgets('a wrapped typed embed is built by the builder of its type, '
      'with its src and style', (tester) async {
    final alt = _Recorder('alt');
    final image = _Recorder('image');
    final builders = crdtQuillEmbedBuilders([alt, image]);
    final controller = _controller(
      {'alt': 'A cat', 'type': 'image', 'src': 'a.png'},
      {'style': 'width: 120'},
    );
    await _show(tester, controller, builders);

    expect(tester.takeException(), isNull);
    expect(alt.contexts, isEmpty);
    final node = image.contexts.single.node;
    expect(node.value.data, 'a.png');
    expect(node.style.attributes['style']?.value, 'width: 120');
  });

  testWidgets('a wrapped embed without a builder gets the fallback', (
    tester,
  ) async {
    final seen = <Map<String, Object?>>[];
    final builders = crdtQuillEmbedBuilders(
      [_Recorder('image')],
      fallback: (context, embed) {
        seen.add(embed);
        return const Text('fallback');
      },
    );
    final controller = _controller({'formula': 'x', 'size': 2});
    await _show(tester, controller, builders);

    expect(tester.takeException(), isNull);
    expect(find.text('fallback', findRichText: true), findsOneWidget);
    expect(seen, [
      {'formula': 'x', 'size': 2},
    ]);
    expect(controller.document.toPlainText(builders), 'a￼\n');
  });

  testWidgets('the default fallback never throws', (tester) async {
    for (final embed in [
      <String, Object?>{},
      'x',
      3,
      {'type': 'image', 'src': 3},
      {'type': 'formula', 'image': 'a.png'},
    ]) {
      await _show(
        tester,
        _controller(embed),
        crdtQuillEmbedBuilders([_Recorder('image')]),
      );
      expect(tester.takeException(), isNull, reason: '$embed');
      expect(
        find.descendant(
          of: find.byType(QuillEditor),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.decoration != null,
          ),
        ),
        findsOneWidget,
        reason: '$embed',
      );
    }
  });

  group('crdtQuillUnknownEmbedBuilder', () {
    late CRDTDocument document;
    late CRDTFugueRichTextHandler page;

    setUp(() {
      document = CRDTDocument(peerId: PeerId.generate());
      page = CRDTFugueRichTextHandler(document, 'page')..insert(0, 'ab');
    });

    tearDown(() => document.dispose());

    Widget editor(QuillController controller, QuillEditorConfig config) =>
        CrdtProvider.value(
          value: document,
          child: MaterialApp(
            home: Scaffold(
              body: CrdtQuillBinder(
                id: 'page',
                controller: controller,
                builder: (context) =>
                    QuillEditor.basic(controller: controller, config: config),
              ),
            ),
          ),
        );

    testWidgets('alone, it shows a peer embed of any type with the fallback', (
      tester,
    ) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final seen = <Map<String, Object?>>[];
      await tester.pumpWidget(
        editor(
          controller,
          QuillEditorConfig(
            unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(
              fallback: (context, embed) {
                seen.add(embed);
                return const Text('fallback');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      page
        ..insertEmbed(2, {'type': 'image', 'src': 'a.png'})
        ..insertEmbed(3, {'mention': 'bob'})
        ..insertEmbed(4, {
          'mention': {'id': 1},
        })
        ..insertEmbed(5, {'alt': 'a', 'type': 'image', 'src': 'b.png'});
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('fallback', findRichText: true), findsNWidgets(4));
      expect(seen, [
        {'type': 'image', 'src': 'a.png'},
        {'mention': 'bob'},
        {
          'mention': {'id': 1},
        },
        {'alt': 'a', 'type': 'image', 'src': 'b.png'},
      ]);
    });

    testWidgets('with the wrapping builders, it draws the default fallback', (
      tester,
    ) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        editor(
          controller,
          QuillEditorConfig(
            embedBuilders: crdtQuillEmbedBuilders(const []),
            unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
          ),
        ),
      );
      await tester.pump();

      page
        ..insertEmbed(2, {'type': 'image', 'src': 'a.png'})
        ..insertEmbed(3, {'mention': 'bob'});
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(QuillEditor),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.decoration != null,
          ),
        ),
        findsNWidgets(2),
      );
    });
  });
}
