@TestOn('vm')
library;

// End-to-end test against a real server. Requires `npx wrangler dev` running
// in ../server; run explicitly with:
//   flutter test --dart-define=E2E=true test/e2e_test.dart
import 'dart:math';
import 'dart:ui';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/sync_client.dart';

const _e2e = bool.fromEnvironment('E2E');

Future<void> _eventually(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

({
  CRDTDocument doc,
  CRDTFugueTextHandler text,
  SyncClient sync,
  AwarenessService awareness,
})
_makeClient(String roomId, String name) {
  final doc = CRDTDocument();
  final text = CRDTFugueTextHandler(doc, kHandlerId);
  final awareness = AwarenessService(
    name: name,
    color: const Color(0xFF3949AB),
  );
  final sync = SyncClient(roomId: roomId, document: doc, awareness: awareness)
    ..connect();
  return (doc: doc, text: text, sync: sync, awareness: awareness);
}

void main() {
  test(
    'two clients converge through the real relay server',
    skip: _e2e ? false : 'requires wrangler dev (run with -DE2E=true)',
    () async {
      final roomId = 'e2e${Random().nextInt(1 << 30)}';
      final a = _makeClient(roomId, 'Ann');
      final b = _makeClient(roomId, 'Bob');
      addTearDown(() {
        a.sync.dispose();
        b.sync.dispose();
        a.awareness.dispose();
        b.awareness.dispose();
      });

      await _eventually(
        () =>
            a.sync.status.value == SyncStatus.connected &&
            b.sync.status.value == SyncStatus.connected,
        reason: 'both clients connected',
      );

      a.text.insert(0, 'hello');
      await _eventually(
        () => b.text.value == 'hello',
        reason: 'A\'s edit reaches B',
      );

      b.text.insert(5, ' world');
      await _eventually(
        () => a.text.value == 'hello world' && b.text.value == 'hello world',
        reason: 'both converge on "hello world"',
      );

      // Awareness: A publishes a cursor, B sees it.
      a.awareness.setLocalCursor(a.text.stablePositionAt(3), null);
      await _eventually(
        () => b.awareness.peers.value.values.any(
          (p) => p.name == 'Ann' && p.base != null,
        ),
        reason: 'B sees Ann\'s cursor',
      );

      // A late joiner catches up from the persisted log/snapshot.
      final c = _makeClient(roomId, 'Cy');
      addTearDown(() {
        c.sync.dispose();
        c.awareness.dispose();
      });
      await _eventually(
        () => c.text.value == 'hello world',
        reason: 'late joiner catches up',
      );
    },
  );
}
