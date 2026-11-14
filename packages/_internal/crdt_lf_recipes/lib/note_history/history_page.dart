// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

/// A page that shows the note of the document above it after each change.
class HistoryPage extends StatelessWidget {
  /// Creates the history of the note.
  const HistoryPage({super.key});

  // #docregion scope
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      // Takes the history as it is now, and shows it to the widgets below.
      body: CrdtHistoryScope(
        // Built once: it reads the view, and rebuilds on every move.
        child: const NotePreview(),
        builder:
            (context, session, preview) => Column(
              children: [
                Expanded(child: preview!),
                HistoryControls(session: session),
              ],
            ),
      ),
    );
  }

  // #enddocregion scope
}

// #docregion preview
/// The text of the note. Inside a history scope it reads the past.
class NotePreview extends StatelessWidget {
  /// Creates the preview of the note.
  const NotePreview({super.key});

  @override
  Widget build(BuildContext context) {
    // The same widget shows the live note outside a history scope.
    return CrdtHandlerBuilder<CRDTFugueTextHandler>(
      id: 'note',
      builder:
          (context, note) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.topLeft, child: Text(note.value)),
          ),
    );
  }
}
// #enddocregion preview

/// Moves the cursor of [session], and says who made the change it stands on.
class HistoryControls extends StatelessWidget {
  /// Creates the controls of [session].
  const HistoryControls({required this.session, super.key});

  /// The history to move through.
  final HistorySession session;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change ${session.cursor} of ${session.length}'),
            Text(describeChange(session)),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: session.canPrevious ? session.previous : null,
                ),
                Expanded(
                  child: Slider(
                    value: session.cursor.toDouble(),
                    // A slider needs a range: an empty history has none.
                    max: session.length == 0 ? 1 : session.length.toDouble(),
                    onChanged:
                        session.length == 0
                            ? null
                            : (value) => session.jump(value.round()),
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: session.canNext ? session.next : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// #docregion describe
/// Who made the change the cursor of [session] stands on, and when.
String describeChange(HistorySession session) {
  // The view holds the changes up to the cursor.
  final changes = session.document.exportChanges();
  if (changes.isEmpty) {
    return 'Before the first change';
  }
  final last = changes.last;
  final author =
      last.author == session.document.peerId
          ? 'You'
          : last.author.id.substring(0, 8);
  final time = last.id.hlc.asDateTime.toLocal();
  final minute = time.minute.toString().padLeft(2, '0');
  return '$author · ${time.hour}:$minute';
}

// #enddocregion describe
