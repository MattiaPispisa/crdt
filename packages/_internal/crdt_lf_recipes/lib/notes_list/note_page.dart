// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/material.dart';

/// A page that edits the note [id] stored in [backend].
class NotePage extends StatefulWidget {
  /// Creates the page of the note [id] stored in [backend].
  const NotePage({
    required this.backend,
    required this.id,
    this.onClosed,
    super.key,
  });

  /// Where the note is stored.
  final CRDTStorageBackend backend;

  /// The id of the note's document.
  final String id;

  /// Called once the note is written and closed, after the page is gone.
  final VoidCallback? onClosed;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  PersistentDocument? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  // #docregion open
  Future<void> _open() async {
    // Reads the stored note (or starts an empty one), then writes every edit.
    final note = await widget.backend.openDocument(widget.id);
    CRDTFugueTextHandler(note.document, 'body');

    if (!mounted) {
      return _close(note, widget.onClosed);
    }
    setState(() => _note = note);
  }
  // #enddocregion open

  // #docregion close
  @override
  void dispose() {
    final note = _note;
    if (note != null) {
      unawaited(_close(note, widget.onClosed));
    }
    super.dispose();
  }

  static Future<void> _close(
    PersistentDocument note,
    VoidCallback? onClosed,
  ) async {
    await note.persistence.dispose(); // writes what is still waiting
    note.document.dispose();
    await note.persistence.storage.close();
    onClosed?.call();
  }
  // #enddocregion close

  // #docregion bind
  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: CrdtProvider.value(
        value: note.document,
        child: CrdtTextFieldBuilder(
          id: 'body',
          builder:
              (context, controller) => TextField(
                controller: controller,
                maxLines: null,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'The first line is the title',
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
        ),
      ),
    );
  }
  // #enddocregion bind
}
