// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

// flutter_quill has a ChangeSource of its own.
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// A page that edits the rich text stored in [backend], with undo.
class EditorPage extends StatefulWidget {
  /// Creates the page of the rich text stored in [backend].
  const EditorPage({required this.backend, super.key});

  /// Where the page is stored.
  final CRDTStorageBackend backend;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  // #docregion state
  // The State owns these: the binder never disposes them, and a new
  // FocusNode on each build would drop the keyboard.
  final _controller = QuillController.basic();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  // #enddocregion state

  PersistentDocument? _page;
  CRDTUndoManager? _undo;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  // #docregion open
  Future<void> _open() async {
    final page = await widget.backend.openDocument('page');
    final text = CRDTFugueRichTextHandler(page.document, 'page');
    // Records only the edits made in this editor.
    final undo = CRDTUndoManager(
      page.document,
      trackedOrigins: {crdtQuillOrigin},
    )..track(text);

    if (!mounted) {
      undo.dispose();
      return _close(page);
    }
    setState(() {
      _page = page;
      _undo = undo;
    });
  }
  // #enddocregion open

  // #docregion close
  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _undo?.dispose();
    final page = _page;
    if (page != null) {
      unawaited(_close(page));
    }
    super.dispose();
  }

  static Future<void> _close(PersistentDocument page) async {
    await page.persistence.dispose(); // writes what is still waiting
    page.document.dispose();
    await page.persistence.storage.close();
  }
  // #enddocregion close

  // #docregion bind
  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Editor')),
      body: CrdtProvider.value(
        value: page.document,
        child: CrdtQuillBinder(
          id: 'page',
          controller: _controller,
          // The editor, its shortcuts and the toolbar buttons undo through it.
          undoManager: _undo,
          builder:
              (context) => Column(
                children: [
                  // The binder gives the controller a new document: key the
                  // toolbar on it, so its undo and redo buttons follow.
                  ListenableBuilder(
                    listenable: _controller,
                    builder:
                        (context, _) => QuillSimpleToolbar(
                          key: ObjectKey(_controller.document),
                          controller: _controller,
                          config: const QuillSimpleToolbarConfig(
                            multiRowsDisplay: false,
                          ),
                        ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: QuillEditor.basic(
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        padding: const EdgeInsets.all(16),
                        // Shows an embed of another peer that has no builder.
                        unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
  // #enddocregion bind
}
