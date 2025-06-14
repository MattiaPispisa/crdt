import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';

/// A message codec that can be used to encode and decode messages
/// for a list of plugins.
///
/// The codec will try to decode the message with each plugin's codec
/// until one of them succeeds.
/// If no plugin can decode the message, the codec will return `null`.
class PluginAwareMessageCodec implements MessageCodec<Message> {
  /// Constructor
  const PluginAwareMessageCodec(this._codecs);

  /// Constructor from plugins
  PluginAwareMessageCodec.fromPlugins({
    required MessageCodec<Message> defaultCodec,
    required List<SyncPlugin> plugins,
  }) : _codecs = [defaultCodec, ...plugins.map((e) => e.messageCodec)];

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
