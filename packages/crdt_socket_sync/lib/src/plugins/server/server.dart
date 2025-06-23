import 'package:crdt_socket_sync/server.dart';

/// Base class for all server plugins.
///
/// `extends` (not ~~implements~~) this class to make the plugin work.
///
/// Once the plugin is attached to the server the `CRDTSocketServer` will
/// be available.
/// 
/// A plugin can be used to extend the server functionality.
/// It can handle custom messages, and listen to events from the server.
abstract class ServerSyncPlugin
    with SocketServerProvider
    implements SyncPlugin {
  /// Called when a new client session is created.
  void onNewSession(ClientSession session);

  /// Called when a message is received from a client, after it has been
  /// decoded.
  ///
  /// This method is called for all messages, not just custom messages
  /// handled by this plugin.
  ///
  /// The plugin can then react to the message, for example by sending a
  /// response to the client.
  ///
  /// If the [session] terminates, this method will not be called again.
  void onMessage(ClientSession session, Message message);

  /// Called when [session] subscribes to a new document.
  void onDocumentRegistered(ClientSession session, String documentId);

  /// Called when [session] is closed.
  void onSessionClosed(ClientSession session);
}
