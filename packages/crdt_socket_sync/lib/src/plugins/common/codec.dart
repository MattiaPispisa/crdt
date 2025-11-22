import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';

/// A message codec that can be used to encode and decode messages
/// for a list of [MessageCodec]s.
///
/// The codec will try to decode the message with each [MessageCodec]
/// until one of them succeeds.
/// If no [MessageCodec] can decode the message, the codec will return `null`.
///
/// This codec is designed to support the plugin system.
/// It is used to encode and decode messages with the default codec and the
/// plugins' codecs.
class PluginAwareMessageCodec implements MessageCodec<Message> {
  /// Constructor
  const PluginAwareMessageCodec(this._codecs);

  /// Constructor from a default codec and a list of plugins
  ///
  /// [defaultCodec] is the first codec used to encode and decode messages.
  factory PluginAwareMessageCodec.fromPlugins({
    required MessageCodec<Message> defaultCodec,
    required List<SyncPlugin> plugins,
  }) {
    return PluginAwareMessageCodec(
      [
        defaultCodec,
        ...plugins.map((e) => e.messageCodec),
      ],
    );
  }

  /// The list of codecs
  final List<MessageCodec<Message>> _codecs;

  @override
  Message? decode(List<int> data) {
    for (final codec in _codecs) {
      final message = codec.decode(data);
      if (message != null) {
        return message;
      }
    }

    return null;
  }

  @override
  List<int>? encode(Message message) {
    for (final codec in _codecs) {
      final data = codec.encode(message);
      if (data != null) {
        return data;
      }
    }
    return null;
  }
}
