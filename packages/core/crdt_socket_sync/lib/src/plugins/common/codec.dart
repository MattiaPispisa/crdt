import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';

/// {@template plugin_aware_message_codec}
/// The codec of the protocol plus one per plugin, picked by message type.
///
/// A message in the plugin range (from [MessageTypeValue.firstPluginValue])
/// belongs to a plugin; anything below it belongs to the protocol. [encode]
/// routes on that, so a plugin's codec is the one that writes its own
/// messages. [decode] has bytes rather than a message, so it asks each codec
/// in turn and takes the first that reads them — a codec answers `null` for a
/// frame that is not its own.
///
/// Either way `null` means no codec here handles that message, which is what
/// a peer running a plugin this build does not have looks like.
/// {@endtemplate}
class PluginAwareMessageCodec implements MessageCodec<Message> {
  /// {@macro plugin_aware_message_codec}
  ///
  /// [defaultCodec] reads and writes the protocol's own messages.
  /// [pluginCodecs] are consulted for the plugin range, in order.
  const PluginAwareMessageCodec({
    required MessageCodec<Message> defaultCodec,
    List<MessageCodec<Message>> pluginCodecs = const [],
  })  : _defaultCodec = defaultCodec,
        _pluginCodecs = pluginCodecs;

  /// {@macro plugin_aware_message_codec}
  ///
  /// Takes the codec of every plugin in [plugins].
  factory PluginAwareMessageCodec.fromPlugins({
    required MessageCodec<Message> defaultCodec,
    required List<SyncPlugin> plugins,
  }) {
    return PluginAwareMessageCodec(
      defaultCodec: defaultCodec,
      pluginCodecs: plugins.map((e) => e.messageCodec).toList(),
    );
  }

  /// The codec for the protocol's own messages.
  final MessageCodec<Message> _defaultCodec;

  /// The codecs of the plugins, for the plugin range.
  final List<MessageCodec<Message>> _pluginCodecs;

  @override
  Message? decode(List<int> data) {
    final message = _tryDecode(_defaultCodec, data);
    if (message != null) {
      return message;
    }

    for (final codec in _pluginCodecs) {
      final message = _tryDecode(codec, data);
      if (message != null) {
        return message;
      }
    }

    return null;
  }

  /// What [codec] reads out of [data], or `null` when it reads nothing.
  ///
  /// A codec declines a frame that is not its own by answering `null`, but one
  /// handed bytes in a shape it does not expect throws instead — and that must
  /// not stop the codecs behind it from being asked.
  static Message? _tryDecode(MessageCodec<Message> codec, List<int> data) {
    try {
      return codec.decode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  List<int>? encode(Message message) {
    if (message.type.value < MessageTypeValue.firstPluginValue) {
      return _defaultCodec.encode(message);
    }

    for (final codec in _pluginCodecs) {
      final data = codec.encode(message);
      if (data != null) {
        return data;
      }
    }

    return null;
  }
}
