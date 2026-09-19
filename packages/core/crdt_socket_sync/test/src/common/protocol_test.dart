import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

void main() {
  group('Protocol.readVersion', () {
    test('reads the version a frame carries', () {
      expect(Protocol.readVersion({'protocolVersion': 7}), 7);
    });

    test('a frame without the field speaks the first version', () {
      // A 0.8.x peer never wrote it, and that is exactly what it spoke.
      expect(Protocol.readVersion({}), Protocol.firstProtocolVersion);
    });
  });

  group('Protocol.protocolVersion', () {
    // A tripwire, not a behaviour check.
    //
    // `Protocol.protocolVersion` is what the handshake compares, but the
    // formats that actually break sync live in `crdt_lf` and each carries its
    // own version. All three are read inside `Message.fromJson`, so a peer
    // that raised one fails in the transport decoder, before any handler is
    // involved and long before anything could report why.
    //
    // If this test fails, one of those formats moved. Bump
    // `Protocol.protocolVersion` so the handshake refuses the pairing, then
    // update the numbers here.
    test('covers the crdt_lf formats the wire carries', () {
      expect(Change.schemaVersion, 3, reason: 'Change layout');
      expect(ChangeCodec.version, 2, reason: 'change list framing');
      expect(Snapshot.schemaVersion, 1, reason: 'snapshot wrapper');
      expect(Protocol.protocolVersion, 1);
    });
  });

  group('Protocol.terminalErrors', () {
    test('is the one place a refusal the client cannot retry is named', () {
      expect(
        Protocol.terminalErrors,
        {
          Protocol.errorUnsupportedProtocolVersion,
          Protocol.errorUnsupportedClient,
        },
      );

      // Every client reads the set instead of naming the codes itself, so a
      // code added there reaches both without being wired up twice.
      for (final code in Protocol.terminalErrors) {
        expect(SyncIncompatibility.isTerminalCode(code), isTrue);
      }
    });

    test('the recoverable codes are not terminal', () {
      for (final code in [
        Protocol.errorOutOfSync,
        Protocol.errorHandshakeFailed,
        Protocol.errorInvalidMessage,
        Protocol.errorDocumentNotFound,
        Protocol.errorTimeout,
        Protocol.errorInternalError,
        Protocol.errorConnectionClosed,
      ]) {
        expect(SyncIncompatibility.isTerminalCode(code), isFalse, reason: code);
      }
    });
  });
}
