import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/simulated/network.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every random delay is the longest one of the level.
class _LongestDelay implements Random {
  @override
  int nextInt(int max) => max - 1;

  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;
}

class _Peer {
  _Peer(SimulatedNetwork network, {CRDTDocument? document})
    : document = document ?? CRDTDocument(documentId: 'doc') {
    list = CRDTListHandler<String>(this.document, 'list', handlerType: 'list');
    client = SimulatedSocketClient(document: this.document, network: network);
  }

  final CRDTDocument document;
  late final CRDTListHandler<String> list;
  late SimulatedSocketClient client;

  void reconnect(SimulatedNetwork network) {
    client.dispose();
    client = SimulatedSocketClient(document: document, network: network);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late SimulatedNetwork network;
  late _Peer a;
  late _Peer b;

  setUp(() async {
    network = SimulatedNetwork()..setOnlineStatus(true);
    a = _Peer(network);
    b = _Peer(network);
    await a.client.connect();
    await b.client.connect();
  });

  tearDown(() {
    a.client.dispose();
    b.client.dispose();
    network.dispose();
  });

  test('a local change reaches the other peer of the document', () async {
    a.list.insert(0, 'x');
    await _settle();

    expect(b.list.value, ['x']);
  });

  test('peers of another document hear nothing', () async {
    final other = _Peer(network, document: CRDTDocument(documentId: 'other'));
    await other.client.connect();

    a.list.insert(0, 'x');
    await _settle();

    expect(other.list.value, isEmpty);
    other.client.dispose();
  });

  test('going offline disconnects every client', () {
    network.setOnlineStatus(false);

    expect(a.client.connectionStatusValue, ConnectionStatus.disconnected);
    expect(b.client.connectionStatusValue, ConnectionStatus.disconnected);
    expect(a.client.sessionId, isNull);
  });

  test('a client cannot connect while the network is offline', () async {
    network.setOnlineStatus(false);

    expect(await a.client.connect(), isFalse);
    expect(a.client.connectionStatusValue, ConnectionStatus.disconnected);
  });

  test('edits made offline converge once back online', () async {
    network.setOnlineStatus(false);
    a.list.insert(0, 'from a');
    b.list.insert(0, 'from b');
    await _settle();
    expect(a.list.value, ['from a']);

    network.setOnlineStatus(true);
    await _settle();

    expect(a.list.value, hasLength(2));
    expect(b.list.value, a.list.value);
  });

  test('a reopened peer catches up what it missed', () async {
    b.client.dispose();
    a.list.insert(0, 'while b was away');
    await _settle();
    expect(b.list.value, isEmpty);

    b.reconnect(network);
    await b.client.connect();
    await _settle();

    expect(b.list.value, ['while b was away']);
  });

  test('a peer behind a garbage collected history gets the snapshot', () async {
    network.setOnlineStatus(false);
    a.list
      ..insert(0, 'one')
      ..insert(1, 'two');
    final snapshot = a.document.takeSnapshot(pruneHistory: false);
    a.document.garbageCollect(snapshot.versionVector);
    expect(a.document.exportChanges(), isEmpty);

    network.setOnlineStatus(true);
    await _settle();

    expect(b.list.value, ['one', 'two']);
  });

  test('a random delay holds a change back, then delivers it', () async {
    final delayed =
        SimulatedNetwork(random: _LongestDelay())
          ..setOnlineStatus(true)
          ..setRandomDelay(true)
          ..setDelayLevel(DelayLevel.low);
    final c = _Peer(delayed);
    final d = _Peer(delayed);
    await c.client.connect();
    await d.client.connect();

    c.list
      ..insert(0, 'first')
      ..insert(1, 'second');
    await _settle();
    expect(d.list.value, isEmpty);

    await Future<void>.delayed(
      Duration(milliseconds: DelayLevel.low.upperBoundMs + 100),
    );
    expect(d.list.value, ['first', 'second']);

    c.client.dispose();
    d.client.dispose();
    delayed.dispose();
  });
}
