// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/widgets/history_controls.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';

/// The room's note as it was after each change, read-only.
///
/// It takes a snapshot of the document in scope when it opens: later edits of
/// the room do not reach it. Open it again to see them.
class HistoryScreen extends StatelessWidget {
  /// Creates the history of the document in scope.
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.historyTitle)),
      body: CrdtHistoryScope(
        child: const PreviewPane(usePlaceholder: false),
        builder: (context, session, preview) => Column(
          children: [
            Expanded(child: preview!),
            HistoryControls(session: session),
          ],
        ),
      ),
    );
  }
}
