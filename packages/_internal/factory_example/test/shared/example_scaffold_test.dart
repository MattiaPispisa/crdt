import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:persistence_conformance/persistence_conformance.dart';

class _LoopbackClient extends CRDTSocketClient {
  _LoopbackClient(this.document);

  @override
  final CRDTDocument document;

  bool disposed = false;

  @override
  PeerId get author => document.peerId;

  @override
  String? get sessionId => null;

  @override
  Stream<Message> get messages => const Stream.empty();

  @override
  Future<bool> connect() async {
    updateConnectionStatus(ConnectionStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    updateConnectionStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendMessage(Message message) async {}

  @override
  Future<void> sendChange(Change change) async {}

  @override
  Future<void> requestSync() async {}

  @override
  void dispose() {
    disposed = true;
    closeClientStreams();
  }
}

class _Sync extends ExampleSync {
  final clients = <_LoopbackClient>[];

  @override
  final List<ExamplePeer> peers = const [
    ExamplePeer(key: 'a', label: 'Peer A'),
    ExamplePeer(key: 'b', label: 'Peer B'),
  ];

  @override
  CRDTSocketClient createClient(CRDTDocument document, ExamplePeer peer) {
    final client = _LoopbackClient(document);
    clients.add(client);
    return client;
  }

  @override
  Widget buildSettings(BuildContext context) => const SizedBox.shrink();
}

// Under fake time, awaiting the cancel of a broadcast subscription never
// completes; the replica close awaits one. Real time windows let it run.
Future<void> _settleClose(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

const _empty = 'No todos yet. Add one using the button below!';

void main() {
  testWidgets('opens one pane per peer, and a reopened screen restores them', (
    tester,
  ) async {
    // Wide surface so both peer panes are laid out side by side.
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sync = _Sync();
    final backends = <String, InMemoryStorageBackend>{};
    await tester.pumpWidget(
      ExampleApp(
        title: 'Examples',
        logo: const SizedBox.shrink(),
        links: const AppBarLinks(docsUrl: '', pubDevUrl: '', pubTooltip: ''),
        primaryColor: Colors.red,
        sync: sync,
        storage:
            (peer) =>
                backends.putIfAbsent(peer.key, InMemoryStorageBackend.new),
      ),
    );

    await tester.tap(find.text('Todo List'));
    await tester.pumpAndSettle();
    expect(find.text(_empty), findsNWidgets(2));

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Buy milk',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await _settleClose(tester);
    expect(sync.clients, hasLength(2));
    expect(sync.clients.every((client) => client.disposed), isTrue);

    await tester.tap(find.text('Todo List'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text(_empty), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await _settleClose(tester);
  });
}
