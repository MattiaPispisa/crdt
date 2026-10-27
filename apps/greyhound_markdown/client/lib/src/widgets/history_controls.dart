// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';

/// The cursor of a [HistorySession]: where it stands, who made that change and
/// when, and a slider with single steps to move it.
class HistoryControls extends StatelessWidget {
  /// Creates the controls of [session].
  const HistoryControls({required this.session, super.key});

  /// The history being browsed.
  final HistorySession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (session.length == 0) {
      return Material(
        elevation: 4,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text(l10n.historyEmpty)),
          ),
        ),
      );
    }

    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.historyChange(session.cursor, session.length),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                _describeLastChange(context),
                key: const Key('history-change-info'),
                style: theme.textTheme.bodySmall,
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.historyPrevious,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: session.canPrevious ? session.previous : null,
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('history-slider'),
                      value: session.cursor.toDouble(),
                      max: session.length.toDouble(),
                      // A tick per change is only readable on a short history.
                      divisions: session.length <= _maxTickedChanges
                          ? session.length
                          : null,
                      onChanged: (value) => session.jump(value.round()),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.historyNext,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: session.canNext ? session.next : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Who made the change the cursor stands on, and when.
  String _describeLastChange(BuildContext context) {
    final l10n = context.l10n;
    final changes = session.document.exportChanges();
    if (changes.isEmpty) {
      return l10n.historyInitial;
    }

    final last = changes.last;
    final author = last.author == session.document.peerId
        ? l10n.historyYou
        : last.author.id.substring(0, 8);
    final time = last.id.hlc.asDateTime.toLocal();
    final material = MaterialLocalizations.of(context);
    return '$author · ${material.formatMediumDate(time)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }
}

/// The longest history whose slider draws a tick for every change.
const int _maxTickedChanges = 100;
