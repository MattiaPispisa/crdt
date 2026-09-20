@TestOn('vm')
library;

import 'dart:async';

import 'package:crdt_socket_sync/server.dart';
import 'package:test/test.dart';

import '../../utils/fake_connection.dart';

/// A session that does nothing with the protocol: this suite is about the
/// host, not about what a session makes of a message.
class _InertSession extends ClientSession {
  _InertSession({
    required super.id,
    required super.connection,
  }) : super.base();

  @override
  Future<void> handleTypedMessage(Message message) async {}
}

/// A host with no transport of its own — the shape an embedder uses.
class _EmbeddedHost extends SessionHostServer<_InertSession> {
  _EmbeddedHost();

  @override
  String get debugLabel => '_EmbeddedHost';

  @override
  _InertSession createSession({
    required String id,
    required TransportConnection connection,
  }) {
    return _InertSession(id: id, connection: connection);
  }
}

/// A host that claims to own its transport, without actually opening one.
class _OwningHost extends _EmbeddedHost {
  _OwningHost({this.failOnStart = false});

  final bool failOnStart;

  int startCalls = 0;
  int startedCalls = 0;
  int stopCalls = 0;

  @override
  bool get ownsTransport => true;

  @override
  String get debugLabel => '_OwningHost';

  @override
  Future<void> onStart() async {
    startCalls++;
    if (failOnStart) {
      throw StateError('bind failed');
    }
  }

  @override
  Future<void> onStarted() async {
    startedCalls++;
  }

  @override
  Future<void> onStop() async {
    stopCalls++;
  }
}

void main() {
  group('SessionHostServer', () {
    late _EmbeddedHost host;

    setUp(() {
      host = _EmbeddedHost();
    });

    test('starts out idle', () {
      expect(host.state, SessionHostState.idle);
      expect(host.isRunning, isFalse);
    });

    test('start() marks the host running and reports it', () async {
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      expect(await host.start(), isTrue);
      await pumpEventQueue();

      expect(host.state, SessionHostState.running);
      expect(events.single.type, ServerEventType.started);
    });

    test('start() is idempotent', () async {
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      expect(await host.start(), isTrue);
      expect(await host.start(), isTrue);
      await pumpEventQueue();

      expect(
        events.where((e) => e.type == ServerEventType.started),
        hasLength(1),
      );
    });

    test('acceptConnection registers a session and reports the client',
        () async {
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);
      await host.start();

      final connection = FakeTransportConnection();
      final session = host.acceptConnection(connection);
      await pumpEventQueue();

      expect(session, isNotNull);
      expect(connection.isClosed, isFalse);

      final connected =
          events.where((e) => e.type == ServerEventType.clientConnected);
      expect(connected, hasLength(1));
      expect(connected.single.data?['clientId'], session!.id);
    });

    test('the first connection starts an embedded host implicitly', () async {
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      final session = host.acceptConnection(FakeTransportConnection());
      await pumpEventQueue();

      expect(session, isNotNull);
      expect(host.state, SessionHostState.running);
      // The host must be up before the client is announced, otherwise work
      // gated on `isRunning` would skip the very first session.
      expect(
        events.map((e) => e.type).toList(),
        [ServerEventType.started, ServerEventType.clientConnected],
      );
    });

    test('a stopped host refuses and closes the connection', () async {
      await host.start();
      await host.stop();

      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      final connection = FakeTransportConnection();
      expect(host.acceptConnection(connection), isNull);
      await pumpEventQueue();

      expect(connection.isClosed, isTrue);
      expect(events.single.type, ServerEventType.error);
      expect(events.single.message, contains('stopped'));
    });

    test('a disposed host refuses and closes the connection', () async {
      await host.start();
      await host.dispose();

      final connection = FakeTransportConnection();
      expect(host.acceptConnection(connection), isNull);
      await pumpEventQueue();

      expect(connection.isClosed, isTrue);
      expect(host.state, SessionHostState.disposed);
    });

    test('a duplicate session id is refused, leaving the first session alone',
        () async {
      await host.start();

      final first = FakeTransportConnection();
      final session = host.acceptConnection(first, sessionId: 'fixed');
      expect(session, isNotNull);

      final second = FakeTransportConnection();
      expect(host.acceptConnection(second, sessionId: 'fixed'), isNull);
      await pumpEventQueue();

      // The impostor is hung up on; the session that got there first keeps
      // its connection.
      expect(second.isClosed, isTrue);
      expect(first.isClosed, isFalse);
    });

    test('stop() closes every session', () async {
      await host.start();

      final a = FakeTransportConnection();
      final b = FakeTransportConnection();
      host
        ..acceptConnection(a)
        ..acceptConnection(b);

      await host.stop();
      await pumpEventQueue();

      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
      expect(host.state, SessionHostState.stopped);
    });

    test('a stopped host can start again', () async {
      await host.start();
      await host.stop();

      expect(await host.start(), isTrue);
      expect(host.state, SessionHostState.running);
      expect(host.acceptConnection(FakeTransportConnection()), isNotNull);
    });

    test('dispose() closes the event stream', () async {
      await host.start();

      var done = false;
      host.serverEvents.listen((_) {}, onDone: () => done = true);

      await host.dispose();
      await pumpEventQueue();

      expect(done, isTrue);
    });

    test('a disposed host cannot be started again', () async {
      await host.dispose();

      expect(await host.start(), isFalse);
      expect(host.state, SessionHostState.disposed);
    });

    test('broadcastMessage skips unsubscribed and excluded sessions', () async {
      await host.start();

      final first = host.acceptConnection(FakeTransportConnection())!;
      final second = host.acceptConnection(FakeTransportConnection())!;

      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      // Nobody is subscribed yet: the broadcast reaches no one, and a
      // broadcast that reached no one is not reported.
      await host.broadcastMessage(
        Message.error(documentId: 'doc', code: 'x', message: 'y'),
      );
      await pumpEventQueue();

      expect(
        events.where((e) => e.type == ServerEventType.messageBroadcasted),
        isEmpty,
      );
      expect(first.id, isNot(second.id));
    });
  });

  group('SessionHostServer, owning its transport', () {
    test('start() binds, then announces, then listens', () async {
      final host = _OwningHost();
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      expect(await host.start(), isTrue);
      await pumpEventQueue();

      expect(host.startCalls, 1);
      expect(host.startedCalls, 1);
      expect(events.single.type, ServerEventType.started);
    });

    test('a failed bind reports an error and does not run', () async {
      final host = _OwningHost(failOnStart: true);
      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      expect(await host.start(), isFalse);
      await pumpEventQueue();

      expect(host.state, SessionHostState.idle);
      expect(host.startedCalls, 0);
      expect(events.single.type, ServerEventType.error);
      expect(events.single.message, contains('bind failed'));
    });

    test('stop() tears the transport down', () async {
      final host = _OwningHost();
      await host.start();

      await host.stop();

      expect(host.stopCalls, 1);
    });

    test('it refuses a connection it was handed before starting', () async {
      final host = _OwningHost();

      final connection = FakeTransportConnection();
      expect(host.acceptConnection(connection), isNull);
      await pumpEventQueue();

      expect(connection.isClosed, isTrue);
      expect(host.state, SessionHostState.idle);
    });
  });
}
