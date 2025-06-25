import 'package:crdt_socket_sync/src/common/common.dart';

/// Base class for all server and client plugins.
///
/// A plugin can be used to extend the server or client functionality.
abstract class SyncPlugin {
  /// The name of the plugin.
  String get name;

  /// The message codec for the plugin.
  ///
  /// This is used to encode and decode messages for the plugin.
  MessageCodec<Message> get messageCodec;

  /// Called when the plugin is disposed.
  ///
  /// Usually [dispose] is called when the server or client is disposed.
  void dispose();
}
