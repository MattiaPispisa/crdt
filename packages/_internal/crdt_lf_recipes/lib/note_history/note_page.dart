// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'history_page.dart';

/// A page that edits the note of the document above it.
class NotePage extends StatelessWidget {
  /// Creates the page of the note.
  const NotePage({super.key});

  void _openHistory(BuildContext context) {
    // A new route is outside the provider: hand the document to it.
    final document = context.crdtDocument;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (context) => CrdtProvider.value(
                value: document,
                child: const HistoryPage(),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => _openHistory(context),
          ),
        ],
      ),
      body: CrdtTextFieldBuilder(
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
    );
  }
}
