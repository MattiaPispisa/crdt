import 'package:crdt_socket_sync/src/common/codec.dart';
import 'package:crdt_socket_sync/src/common/message.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';
import 'package:crdt_socket_sync/src/server/client_session.dart';

class ServerAwarenessPlugin implements ServerSyncPlugin {
  ServerAwarenessPlugin() : _documentAwareness = {};

  @override
  String get name => 'awareness';

  final Map<String, DocumentAwareness> _documentAwareness;

  @override
  void dispose() {
    _documentAwareness.clear();
  }

  @override
  MessageCodec<Message> get messageCodec => JsonMessageCodec(
        toJson: (message) => message.toJson(),
        fromJson: AwarenessMessage.fromJson,
      );

  @override
  void onMessage(ClientSession session, Message message) {}

  @override
  void onNewSession(ClientSession session) {
    // TODO: implement onNewSession
  }

  @override
  void onSessionClosed(ClientSession session) {
    // TODO: implement onSessionClosed
  }
}
