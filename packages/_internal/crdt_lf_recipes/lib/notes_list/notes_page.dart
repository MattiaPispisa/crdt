// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/material.dart';

import 'note_page.dart';

/// A note in the list: its document id and its title.
typedef NoteSummary = ({String id, String title});

/// A page that lists the notes stored in [backend].
class NotesPage extends StatefulWidget {
  /// Creates the list of the notes stored in [backend].
  const NotesPage({required this.backend, super.key});

  /// Where the notes are stored, one document per note.
  final CRDTStorageBackend backend;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<NoteSummary>? _notes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // #docregion load
  Future<void> _load() async {
    final notes = <NoteSummary>[];
    for (final id in await widget.backend.documentIds) {
      // A read-only copy: nothing writes it, so dispose it after reading.
      final document = await widget.backend.readDocument(id);
      final body = CRDTFugueTextHandler(document, 'body').value;
      document.dispose();

      final title = body.split('\n').first.trim();
      notes.add((id: id, title: title.isEmpty ? 'Empty note' : title));
    }
    notes.sort((a, b) => a.id.compareTo(b.id));

    if (mounted) {
      setState(() => _notes = notes);
    }
  }
  // #enddocregion load

  // #docregion actions
  Future<void> _create() {
    // The document id is the note id: any string that is unique in the app.
    return _edit('note-${DateTime.now().microsecondsSinceEpoch}');
  }

  Future<void> _edit(String id) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        // The list reloads once the note is written and closed.
        builder:
            (context) =>
                NotePage(backend: widget.backend, id: id, onClosed: _load),
      ),
    );
  }

  Future<void> _delete(String id) async {
    // A dismissed row must leave the list at once.
    setState(() => _notes = [...?_notes?.where((note) => note.id != id)]);
    // The changes, the snapshots and the identity of the note.
    await widget.backend.deleteDocument(id);
  }
  // #enddocregion actions

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New note',
        onPressed: () => unawaited(_create()),
        child: const Icon(Icons.add),
      ),
      body:
          notes == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  for (final note in notes)
                    Dismissible(
                      key: ValueKey(note.id),
                      onDismissed: (_) => unawaited(_delete(note.id)),
                      child: ListTile(
                        title: Text(note.title),
                        onTap: () => unawaited(_edit(note.id)),
                      ),
                    ),
                ],
              ),
    );
  }
}
