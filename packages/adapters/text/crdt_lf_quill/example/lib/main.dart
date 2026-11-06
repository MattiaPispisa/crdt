// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

const _pageId = 'page';

void main() => runApp(const QuillExampleApp());

class QuillExampleApp extends StatelessWidget {
  const QuillExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'crdt_lf_quill',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: TwoPeers(),
    );
  }
}

/// Two peers of the same document, side by side. Each local change is sent
/// to the other peer, in order, as a network would.
class TwoPeers extends StatefulWidget {
  const TwoPeers({super.key});

  @override
  State<TwoPeers> createState() => _TwoPeersState();
}

class _TwoPeersState extends State<TwoPeers> {
  final _alice = CRDTDocument(peerId: PeerId.generate());
  final _bob = CRDTDocument(peerId: PeerId.generate());
  late final List<StreamSubscription<Change>> _links;

  // What a presence channel would carry: each peer's cursor, for the other.
  CrdtTextCursor? _aliceCursor;
  CrdtTextCursor? _bobCursor;

  @override
  void initState() {
    super.initState();
    CRDTFugueRichTextHandler(_alice, _pageId);
    CRDTFugueRichTextHandler(_bob, _pageId);
    _links = [
      _alice.localChanges.listen(_bob.applyChange),
      _bob.localChanges.listen(_alice.applyChange),
    ];
  }

  @override
  void dispose() {
    for (final link in _links) {
      unawaited(link.cancel());
    }
    _alice.dispose();
    _bob.dispose();
    super.dispose();
  }

  CrdtTextCursor? _cursor(
    String label,
    Color color,
    FugueElementID? base,
    FugueElementID? extent,
  ) {
    if (base == null || extent == null) {
      return null;
    }
    return CrdtTextCursor(
      id: label,
      color: color,
      label: label,
      base: base,
      extent: extent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('crdt_lf_quill: two peers')),
      body: Row(
        children: [
          Expanded(
            child: _Peer(
              label: 'Alice',
              document: _alice,
              remoteCursor: _bobCursor,
              onAnchors: (base, extent) => setState(
                () =>
                    _aliceCursor = _cursor('Alice', Colors.teal, base, extent),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _Peer(
              label: 'Bob',
              document: _bob,
              remoteCursor: _aliceCursor,
              onAnchors: (base, extent) => setState(
                () => _bobCursor = _cursor(
                  'Bob',
                  Colors.deepOrange,
                  base,
                  extent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Peer extends StatefulWidget {
  const _Peer({
    required this.label,
    required this.document,
    required this.remoteCursor,
    required this.onAnchors,
  });

  final String label;
  final CRDTDocument document;
  final CrdtTextCursor? remoteCursor;
  final void Function(FugueElementID? base, FugueElementID? extent) onAnchors;

  @override
  State<_Peer> createState() => _PeerState();
}

class _PeerState extends State<_Peer> {
  final _controller = QuillController.basic();

  // Kept here because cursors rebuild the editor: `QuillEditor.basic` would
  // make a new focus node on each build and drop the keyboard.
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CrdtProvider.value(
      value: widget.document,
      child: CrdtQuillBinder(
        id: _pageId,
        controller: _controller,
        onSelectionAnchorsChanged: widget.onAnchors,
        onUnsupported: (_) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Part of the edit was not written')),
        ),
        builder: (context) => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              QuillSimpleToolbar(
                controller: _controller,
                config: const QuillSimpleToolbarConfig(multiRowsDisplay: false),
              ),
              const Divider(),
              Expanded(
                child: CrdtQuillCursorsOverlay(
                  id: _pageId,
                  cursors: [?widget.remoteCursor],
                  child: QuillEditor.basic(
                    controller: _controller,
                    focusNode: _focusNode,
                    scrollController: _scrollController,
                    config: QuillEditorConfig(
                      placeholder: '${widget.label} writes here',
                      unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
