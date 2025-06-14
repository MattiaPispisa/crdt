import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';
import 'package:crdt_socket_sync/src/server/client_session.dart';

/// Base class for all server plugins.
///
/// A plugin can be used to extend the server functionality.
/// It can handle custom messages, and listen to events from the server.
abstract class ServerSyncPlugin implements SyncPlugin {
  /// Called when a new client session is created.
  ///
  /// This is a good place to add listeners to the session's events.
  void onNewSession(ClientSession session);

  /// Called when a message is received from a client, after it has been
  /// decoded.
  ///
  /// This method is called for all messages, not just custom messages
  /// handled by this plugin.
  /// The plugin can then react to the message, for example by sending a
  /// response to the client.
  void onMessage(ClientSession session, Message message);

  /// Called when a session is closed.
  void onSessionClosed(ClientSession session);
}
