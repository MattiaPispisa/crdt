// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_chip.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

const int _oneDay = 24 * 60 * 60 * 1000;

/// The wall time `HH:mm:ss.SSS` of the clock [l], with `+c` when the
/// counter [c] is above 0.
///
/// A clock below one day is not a wall time, so it stays raw: `l.c`.
String clockLabel(int l, int c) {
  if (l < _oneDay) return '$l.$c';
  final t = DateTime.fromMillisecondsSinceEpoch(l);
  String two(int n) => n.toString().padLeft(2, '0');
  final time =
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
  return c > 0 ? '$time +$c' : time;
}

/// The name of an operation [kind]; `unknown` when the envelope is not
/// readable.
String kindLabel(int? kind) => switch (kind) {
  null => 'unknown',
  0 => 'insert',
  1 => 'delete',
  2 => 'update',
  3 => 'move',
  _ => 'kind $kind',
};

/// A row of the change list: clock, author, handler, kind and size.
class ChangeRow extends StatelessWidget {
  const ChangeRow({
    required this.entry,
    required this.local,
    required this.selected,
    required this.onTap,
    this.graph,
    super.key,
  });

  final MirrorEntry entry;

  /// Whether the author is the peer of the document.
  final bool local;

  final bool selected;

  final VoidCallback onTap;

  /// Drawn at the start of the row; `null` for none.
  final Widget? graph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = entry.change;
    return Material(
      color:
          selected
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (graph case final graph?) graph,
            const SizedBox(width: densePadding),
            SizedBox(
              width: 110,
              child: Text(
                clockLabel(change.hlc.l, change.hlc.c),
                style: theme.fixedFontStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(child: PeerChip(change.author.toString(), local: local)),
            const SizedBox(width: denseSpacing),
            Expanded(
              child: Text(
                entry.handlerId ?? '?',
                style: theme.fixedFontStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: densePadding),
            Text(kindLabel(entry.kind), style: theme.subtleTextStyle),
            const SizedBox(width: densePadding),
            Text('${entry.byteLength} B', style: theme.subtleTextStyle),
            const SizedBox(width: densePadding),
          ],
        ),
      ),
    );
  }
}
