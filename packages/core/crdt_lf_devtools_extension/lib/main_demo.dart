// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/screen.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

/// The tool on two demo documents of this process, without DevTools.
///
/// Run it with `fvm flutter run -d chrome -t lib/main_demo.dart`.
void main() {
  runApp(_DemoApp(_Demo()));
}

class _Demo {
  _Demo()
    : a = CRDTDocument(peerId: PeerId.generate(), documentId: 'demo'),
      b = CRDTDocument(peerId: PeerId.generate(), documentId: 'demo') {
    for (final doc in [a, b]) {
      _open(doc);
    }
    _textOf(a).insert(0, 'Hello');
    _sync();
    _textOf(a).insert(5, ' from A');
    _textOf(b).insert(0, 'B says: ');
    _sync();

    final fugue = CRDTFugueTextHandler(a, 'fugue-text')..insert(0, 'fugue');
    CRDTListHandler<int>(a, 'list', handlerType: 'int-list')
      ..insert(0, 1)
      ..insert(1, 2);
    CRDTFugueListHandler<int>(a, 'fugue-list', handlerType: 'int-fugue-list')
      ..insert(0, 3)
      ..insert(1, 4);
    CRDTFugueMovableListHandler<String>(a, 'movable', handlerType: 'tasks')
      ..insert(0, 'first')
      ..insert(1, 'second')
      ..move(0, 1);
    CRDTMapHandler<int>(a, 'map', handlerType: 'int-map').set('k', 4);
    CRDTRegisterHandler<String>(
      a,
      'register',
      handlerType: 'title',
    ).set('title');
    CRDTORSetHandler<String>(a, 'or-set', handlerType: 'tags').add('crdt');
    CRDTORMapHandler<String, int>(
      a,
      'or-map',
      handlerType: 'scores',
    ).put('alice', 3);
    CRDTFugueRichTextHandler(a, 'rich')
      ..insert(0, 'Rich text')
      ..format(0, 4, 'bold', true);

    final child = CRDTTextHandler(a, 'nested-text')..insert(0, 'nested');
    CRDTMapRefHandler(a, 'root').setRef('child', child);

    final gone = CRDTMapHandler<int>(a, 'gone', handlerType: 'int-map')
      ..set('k', 1);
    a.deleteHandler(gone);

    CRDTUndoManager(a).track(fugue);
    _sync();
    a.takeSnapshot();
  }

  final CRDTDocument a;

  final CRDTDocument b;

  int _edits = 0;

  static void _open(CRDTDocument doc) => CRDTTextHandler(doc, 'text');

  static CRDTTextHandler _textOf(CRDTDocument doc) =>
      doc.registeredHandlers['text']! as CRDTTextHandler;

  void _sync() {
    a.importChanges(b.exportChanges());
    b.importChanges(a.exportChanges());
  }

  void edit() {
    _edits++;
    _textOf(a).insert(0, 'a$_edits ');
    _textOf(b).insert(0, 'b$_edits ');
    _sync();
  }

  /// Adds [count] one-character edits, half on each peer, synced every
  /// 100 edits.
  void addMany([int count = 10000]) {
    for (var i = 0; i < count ~/ 2; i++) {
      _textOf(a).insert(0, 'a');
      _textOf(b).insert(0, 'b');
      if (i % 100 == 99) _sync();
    }
    _sync();
  }
}

class _DemoApp extends StatefulWidget {
  const _DemoApp(this.demo);

  final _Demo demo;

  @override
  State<_DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<_DemoApp> {
  final InProcessBridge _bridge = InProcessBridge();

  bool _dark = true;

  ThemeData _theme({required bool dark}) => themeFor(
    isDarkTheme: dark,
    ideTheme: IdeTheme(),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: dark ? darkColorScheme : lightColorScheme,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(dark: false),
      darkTheme: _theme(dark: true),
      home: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(denseSpacing),
              child: Row(
                children: [
                  const Text('Dark'),
                  Switch(
                    value: _dark,
                    onChanged: (value) => setState(() => _dark = value),
                  ),
                  const SizedBox(width: defaultSpacing),
                  DevToolsButton(
                    icon: Icons.edit,
                    label: 'Add edits',
                    onPressed: widget.demo.edit,
                  ),
                  const SizedBox(width: denseSpacing),
                  DevToolsButton(
                    icon: Icons.playlist_add,
                    label: '10 000 changes',
                    onPressed: widget.demo.addMany,
                  ),
                ],
              ),
            ),
            Expanded(child: CrdtLfScreen(bridge: _bridge)),
          ],
        ),
      ),
    );
  }
}
