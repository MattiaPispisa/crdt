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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('crdt_lf_quill: two peers')),
      body: Row(
        children: [
          Expanded(
            child: _Peer(label: 'Alice', document: _alice),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _Peer(label: 'Bob', document: _bob),
          ),
        ],
      ),
    );
  }
}

class _Peer extends StatefulWidget {
  const _Peer({required this.label, required this.document});

  final String label;
  final CRDTDocument document;

  @override
  State<_Peer> createState() => _PeerState();
}

class _PeerState extends State<_Peer> {
  final _controller = QuillController.basic();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CrdtProvider.value(
      value: widget.document,
      // The toolbar and the editor listen to the controller: keep them under
      // the binder.
      child: CrdtQuillBinder(
        id: _pageId,
        controller: _controller,
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
                child: QuillEditor.basic(
                  controller: _controller,
                  config: QuillEditorConfig(
                    placeholder: '${widget.label} writes here',
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
