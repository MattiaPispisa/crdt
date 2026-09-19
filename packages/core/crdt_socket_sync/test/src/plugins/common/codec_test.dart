import 'dart:convert';

import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/codec.dart';
import 'package:test/test.dart';

/// A message type in the plugin range.
enum _PluginType implements MessageTypeValue {
  greet(MessageTypeValue.firstPluginValue);

  const _PluginType(this.value);

  @override
  final int value;
}

class _PluginMessage extends Message {
  const _PluginMessage({required String documentId})
      : super(_PluginType.greet, documentId);

  @override
  Map<String, dynamic> toJson() => {
        'type': _PluginType.greet.value,
        'documentId': documentId,
      };
}

/// A codec that does not produce JSON, so a test can tell whose bytes these
/// are. A plugin with an envelope, a binary layout or encryption looks like
/// this one.
class _MarkedCodec implements MessageCodec<Message> {
  const _MarkedCodec();

  static const int marker = 0xAA;

  @override
  List<int>? encode(Message message) =>
      message is _PluginMessage ? [marker, ...utf8.encode(message.documentId)] : null;

  @override
  Message? decode(List<int> data) => data.isNotEmpty && data.first == marker
      ? _PluginMessage(documentId: utf8.decode(data.skip(1).toList()))
      : null;
}

void main() {
  final defaultCodec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: Message.fromJson,
  );

  PluginAwareMessageCodec codec() => PluginAwareMessageCodec(
        defaultCodec: defaultCodec,
        pluginCodecs: const [_MarkedCodec()],
      );

  group('PluginAwareMessageCodec', () {
    test("writes a plugin's message with that plugin's codec", () {
      // The default codec can encode anything — `toJson` is polymorphic — so
      // without routing by type it claimed every message and a plugin's
      // encoder never ran. A plugin whose bytes are not the default JSON then
      // sent the wrong ones, and the peer refused them.
      final data = codec().encode(const _PluginMessage(documentId: 'doc'))!;

      expect(data.first, _MarkedCodec.marker);
    });

    test("writes the protocol's own message with the default codec", () {
      final data =
          codec().encode(Message.ping(documentId: 'doc', timestamp: 0))!;

      expect(data.first, isNot(_MarkedCodec.marker));
      expect(jsonDecode(utf8.decode(data)), isA<Map<String, dynamic>>());
    });

    test('answers null for a plugin message no codec here handles', () {
      final bare = PluginAwareMessageCodec(defaultCodec: defaultCodec);

      expect(bare.encode(const _PluginMessage(documentId: 'doc')), isNull);
    });

    test('reads back what either side wrote', () {
      final plugin = codec().encode(const _PluginMessage(documentId: 'doc'))!;
      final core = codec().encode(Message.ping(documentId: 'doc', timestamp: 0))!;

      expect(codec().decode(plugin), isA<_PluginMessage>());
      expect(codec().decode(core), isA<PingMessage>());
    });
  });
}
