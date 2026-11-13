// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/material.dart';

/// A page that edits the note stored in [backend].
class NotePage extends StatefulWidget {
  /// Creates the page of the note stored in [backend].
  const NotePage({required this.backend, super.key});

  /// Where the note is stored.
  final CRDTStorageBackend backend;

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
    final note = await widget.backend.openDocument(
      'note',
      // Past this many stored changes, a snapshot replaces them.
      compactAfter: 1000,
      // Without it, a write that fails is silent.
      onError: (error, stack) => debugPrint('Storage error: $error'),
    );
    CRDTFugueTextHandler(note.document, 'note');

    if (!mounted) {
      return _close(note);
    }
    setState(() => _note = note);
  }
  // #enddocregion open

  // #docregion close
  @override
  void dispose() {
    final note = _note;
    if (note != null) {
      unawaited(_close(note));
    }
    super.dispose();
  }

  static Future<void> _close(PersistentDocument note) async {
    await note.persistence.dispose(); // writes what is still waiting
    note.document.dispose();
    await note.persistence.storage.close();
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
          id: 'note',
          builder:
              (context, controller) => TextField(
                controller: controller,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Write here',
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
        ),
      ),
    );
  }
  // #enddocregion bind
}
