import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';

class ClientAwarenessPlugin implements ClientSyncPlugin {
  ClientAwarenessPlugin({
    required CRDTSocketClient client,
    MessageCodec<Message>? codec,
  })  : _client = client,
        messageCodec = codec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: Message.fromJson,
            );

  final CRDTSocketClient _client;

  @override
  String get name => 'awareness';

  @override
  final MessageCodec<Message> messageCodec;
  @override
  void onMessage(Message message) {
    if (message is! AwarenessStateMessage) {
      return;
    }

    switch (message.type) {
      case AwarenessMessageType.awarenessState:
        _handleAwarenessState(message as AwarenessStateMessage);
        return;
      case AwarenessMessageType.awarenessUpdate:
        _handleAwarenessUpdate(message as AwarenessUpdateMessage);
        return;
      case AwarenessMessageType.awarenessQuery:
        return;
    }
  }

  void _handleAwarenessState(AwarenessStateMessage message) {
    // TODO: sovrascrivere lo stato locale dell'awareness con quello del server
  }

  void _handleAwarenessUpdate(AwarenessUpdateMessage message) {
    // TODO: aggiornare lo stato locale dell'awareness
  }

  void updateLocalState(
    String documentId,
    String clientId,
    ClientAwareness state,
  ) {
    // aggiornare lo stato locale dell'awareness e poi innviarlo al server
  }

  void requestState(String documentId) {
    // TODO: inviare un messaggio al server per ottenere lo stato dell'awareness
  }

  @override
  void onConnected() {
    // TODO: alla connessione inviamo subito un initial awareness state?
    return;
  }

  @override
  void onDisconnected() {
    // server is aware of client leaving so we don't need to do anything
    return;
  }
}
