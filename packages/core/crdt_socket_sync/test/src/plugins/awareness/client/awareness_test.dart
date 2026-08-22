import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/plugins/awareness/client/awareness.dart';
import 'package:crdt_socket_sync/src/plugins/awareness/common/message.dart';
import 'package:crdt_socket_sync/src/plugins/awareness/common/model.dart';
import 'package:test/test.dart';

import '../../../utils/mock_socket_client.dart';

void main() {
  group('ClientAwarenessPlugin state merge', () {
    // MockCRDTSocketClient reports this fixed session id.
    const sessionId = 'test-session-id';

    late CRDTDocument doc;
    late ClientAwarenessPlugin plugin;
    late MockCRDTSocketClient client;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate(), documentId: 'doc');
      plugin = ClientAwarenessPlugin();
      client = MockCRDTSocketClient(
        document: doc,
        author: doc.peerId,
        plugins: [plugin],
      );
    });

    tearDown(() {
      plugin.dispose();
      client.dispose();
    });

    AwarenessStateMessage serverState(Map<String, ClientAwareness> states) {
      return AwarenessStateMessage(
        documentId: 'doc',
        awareness: DocumentAwareness(documentId: 'doc', states: states),
      );
    }

    test('preserves the local own entry absent from the server state', () {
      plugin.updateLocalState({'cursor': 5});
      expect(plugin.awareness.states[sessionId]?.metadata['cursor'], 5);

      // Server pushes a full state that does not yet include our latest update.
      plugin.onMessage(
        serverState({
          'other': const ClientAwareness(
            clientId: 'other',
            metadata: {'cursor': 1},
          ),
        }),
      );

      // Regression: the local own entry used to be clobbered by the server
      // state. It must survive, and the remote entry must be merged in.
      expect(plugin.awareness.states[sessionId]?.metadata['cursor'], 5);
      expect(plugin.awareness.states['other']?.metadata['cursor'], 1);
    });

    test('local own entry wins over a stale server entry for this client', () {
      plugin
        ..updateLocalState({'cursor': 9})
        // Server has an older value for our own client.
        ..onMessage(
          serverState({
            sessionId: const ClientAwareness(
              clientId: sessionId,
              metadata: {'cursor': 2},
            ),
          }),
        );

      expect(plugin.awareness.states[sessionId]?.metadata['cursor'], 9);
    });
  });
}
