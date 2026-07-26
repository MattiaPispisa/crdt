import 'dart:async';

import 'package:crdt_socket_sync/src/common/client/handshake_gate.dart';
import 'package:test/test.dart';

void main() {
  group('HandshakeGate', () {
    test('starts inactive', () {
      final gate = HandshakeGate();

      expect(gate.isActive, isFalse);
      expect(gate.inProgress, isFalse);
      expect(gate.pending, isNull);
      expect(gate.completed, completion(isFalse));
    });

    test('succeed wins the race against the timeout', () async {
      final gate = HandshakeGate();

      final result = gate.perform(
        send: () async {
          // Reply arrives before the (long) timeout could fire.
          scheduleMicrotask(gate.succeed);
        },
        timeout: const Duration(seconds: 10),
      );

      expect(await result, isTrue);
      expect(gate.completed, completion(isTrue));
      // A resolved handshake stays active until reset.
      expect(gate.isActive, isTrue);
      expect(gate.inProgress, isFalse);
      expect(gate.pending, isNull);
    });

    test('resolves false when the timeout wins', () async {
      final gate = HandshakeGate();

      final result = await gate.perform(
        send: () async {},
        timeout: Duration.zero,
      );

      expect(result, isFalse);
      // The completer itself never resolved: gate is still gating sends.
      expect(gate.completed, completion(isFalse));
    });

    test('resolves false when send throws', () async {
      final gate = HandshakeGate();

      final result = await gate.perform(
        send: () async => throw StateError('boom'),
        timeout: const Duration(seconds: 10),
      );

      expect(result, isFalse);
      expect(gate.completed, completion(isFalse));
    });

    test('pending exposes the in-flight future while in progress', () async {
      final gate = HandshakeGate();

      final result = gate.perform(
        send: () async {},
        timeout: const Duration(seconds: 10),
      );

      expect(gate.inProgress, isTrue);
      final pending = gate.pending;
      expect(pending, isNotNull);

      gate.succeed();

      expect(await pending!, isTrue);
      expect(await result, isTrue);
    });

    test('reset fails an in-flight handshake and clears the gate', () async {
      final gate = HandshakeGate();

      final result = gate.perform(
        send: () async {},
        timeout: const Duration(seconds: 10),
      );

      gate.reset();

      expect(await result, isFalse);
      expect(gate.isActive, isFalse);
      expect(gate.inProgress, isFalse);
      expect(gate.pending, isNull);
    });

    test('succeed is a no-op when no handshake is in flight', () {
      final gate = HandshakeGate();

      // Must not throw with no active completer.
      expect(gate.succeed, returnsNormally);
      expect(gate.isActive, isFalse);
    });

    test('a duplicate succeed does not throw', () async {
      final gate = HandshakeGate();

      final result = gate.perform(
        send: () async {},
        timeout: const Duration(seconds: 10),
      );

      gate.succeed();
      // A late/duplicate reply must not throw on the resolved completer.
      expect(gate.succeed, returnsNormally);
      expect(await result, isTrue);
    });
  });
}
