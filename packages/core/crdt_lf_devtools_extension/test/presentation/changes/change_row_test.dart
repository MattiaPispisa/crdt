// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clockLabel shows the wall time, or the raw clock below one day', () {
    final l = DateTime(2026, 11, 17, 9, 5, 3, 42).millisecondsSinceEpoch;
    expect(clockLabel(l, 0), '09:05:03.042');
    expect(clockLabel(l, 3), '09:05:03.042 +3');
    expect(clockLabel(1234, 2), '1234.2');
  });

  test('kindLabel names the four common kinds', () {
    expect(
      [
        for (final k in [0, 1, 2, 3, 7, null]) kindLabel(k),
      ],
      ['insert', 'delete', 'update', 'move', 'kind 7', 'unknown'],
    );
  });

  testWidgets('a row shows the change and reports a tap', (tester) async {
    final doc = CRDTDocument();
    CRDTTextHandler(doc, 'notes').insert(0, 'hi');
    final change = doc.exportChanges().single;
    final entry = MirrorEntry.decode(change.toBytes());
    var taps = 0;

    Future<void> pump({required bool local}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeRow(
            entry: entry,
            local: local,
            selected: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await pump(local: true);
    expect(find.text(clockLabel(change.hlc.l, change.hlc.c)), findsOneWidget);
    expect(find.text(doc.peerId.toString().substring(0, 8)), findsOneWidget);
    expect(find.text(PeerChip.localLabel), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('insert'), findsOneWidget);
    expect(find.text('${entry.byteLength} B'), findsOneWidget);

    await tester.tap(find.text('notes'));
    expect(taps, 1);

    await pump(local: false);
    expect(find.text(PeerChip.localLabel), findsNothing);
    doc.dispose();
  });
}
