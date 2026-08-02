import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/line_number_gutter.dart';

import 'helpers/memory_storage.dart';

/// The [RenderEditable] under [root] — the object that says how the text was
/// actually laid out.
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

/// The editor as [EditorScreen] mounts it: under the document and under the
/// settings the two view options come from.
Widget _app({
  required CRDTDocument document,
  required AwarenessService awareness,
  required UserSettingsCubit settings,
  TargetPlatform? platform,
}) {
  return BlocProvider<UserSettingsCubit>.value(
    value: settings,
    child: CrdtProvider.value(
      value: document,
      child: MaterialApp(
        theme: platform == null ? null : ThemeData(platform: platform),
        home: Scaffold(body: EditorPane(awareness: awareness)),
      ),
    ),
  );
}

/// A document plus an awareness service wired like [EditorScreen] does.
///
/// The (never connected) relay client is what attaches the awareness plugin;
/// without it every cursor publication throws, since the plugin reads its
/// client as soon as the selection moves.
({CRDTDocument document, AwarenessService awareness}) _room() {
  final document = CRDTDocument(peerId: PeerId.generate());
  CRDTFugueTextHandler(document, kHandlerId);
  final awareness = AwarenessService(name: 'me', color: Colors.teal);
  final sync = WebSocketRelayClient(
    url: 'ws://localhost',
    document: document,
    author: document.peerId,
    plugins: [awareness.plugin],
  );
  addTearDown(sync.dispose);
  addTearDown(awareness.dispose);
  addTearDown(document.dispose);
  return (document: document, awareness: awareness);
}

void main() {
  testWidgets('empty editor shows the welcome as a scrollable placeholder that '
      'disappears once the document has content', (tester) async {
    final room = _room();

    await tester.pumpWidget(
      _app(
        document: room.document,
        awareness: room.awareness,
        settings: UserSettingsCubit(storage: MemoryStorage()),
      ),
    );

    // The whole welcome is rendered, inside a scroll view (not a clipped hint).
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(kPlaceholderMarkdown),
      ),
      findsOneWidget,
    );

    // Typing removes the placeholder.
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text(kPlaceholderMarkdown), findsNothing);

    // Let the awareness throttle timer drain before teardown.
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the platform chord applies the matching toolbar action', (
    tester,
  ) async {
    final room = _room();

    await tester.pumpWidget(
      _app(
        document: room.document,
        awareness: room.awareness,
        settings: UserSettingsCubit(storage: MemoryStorage()),
        platform: TargetPlatform.windows,
      ),
    );

    // Focus the field directly: the empty-document placeholder sits on top of
    // it and would swallow the tap.
    await tester.showKeyboard(find.byType(TextField));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '****');
    expect(field.controller!.selection.baseOffset, 2);

    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the view options change the layout without remounting the '
      'field', (tester) async {
    final room = _room();
    final settings = UserSettingsCubit(storage: MemoryStorage());

    await tester.pumpWidget(
      _app(
        document: room.document,
        awareness: room.awareness,
        settings: settings,
      ),
    );
    // A line far too long for the pane, so word wrap has something to do.
    await tester.enterText(find.byType(TextField), 'one\ntwo\n${'x' * 400}');
    await tester.pump();

    // The defaults: no gutter, and the field is exactly as wide as its pane.
    expect(find.byType(LineNumberGutter), findsNothing);
    final paneWidth = tester.getSize(find.byType(EditorSurface)).width;
    expect(tester.getSize(find.byType(TextField)).width, paneWidth);

    // The state the CRDT binding keeps: it has to survive both toggles, or a
    // change of settings would drop focus and the caret mid-typing.
    final editorState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );

    settings
      ..setShowLineNumbers(value: true)
      ..setWordWrap(value: false);
    await tester.pump();

    expect(find.byType(LineNumberGutter), findsOneWidget);
    // The gutter must be as tall as the pane. It paints its numbers itself,
    // and a CustomPaint with no child collapses to zero height unless the row
    // stretches it — which is silent: the widget is there, drawing nothing.
    final gutter = tester.getSize(find.byType(LineNumberGutter));
    expect(gutter.width, greaterThan(0));
    expect(gutter.height, tester.getSize(find.byType(EditorSurface)).height);

    // The field is laid out wider than what is left of the pane...
    expect(
      tester.getSize(find.byType(TextField)).width,
      greaterThan(paneWidth - gutter.width),
    );
    // ...and wide enough that the long line takes a single row: three logical
    // lines, three visual ones. Measuring the text by hand read short here,
    // and the line wrapped anyway.
    final editable = _editableUnder(tester.renderObject(find.byType(TextField)));
    expect(
      editable.size.height / editable.preferredLineHeight,
      closeTo(3, 0.01),
    );

    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editorState),
    );

    await tester.pump(const Duration(milliseconds: 100));
  });
}
