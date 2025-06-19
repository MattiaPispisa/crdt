import 'package:crdt_socket_sync/src/common/common.dart';

/// Base class for all server plugins.
///
/// A plugin can be used to extend the server functionality.
/// It can handle custom messages, and listen to events from the server.
abstract class SyncPlugin {
  /// The name of the plugin.
  String get name;

  /// The message codec for the plugin.
  ///
  /// This is used to encode and decode messages for the plugin.
  /// The default implementation is [CompressedCodec] with [NoCompression].
  MessageCodec<Message> get messageCodec;

  /// Called when the plugin is disposed.
  ///
  /// Usually [dispose] is called when the server is disposed.
  void dispose();
}
