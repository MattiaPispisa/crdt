import 'dart:async';
import 'package:crdt_socket_sync/server.dart';

/// Server awareness plugin.
///
/// This plugin is used to manage the awareness of the clients
/// connected to the same document.
class ServerAwarenessPlugin extends ServerSyncPlugin {
  /// Constructor
  ///
  /// [codec] is the codec to use to encode and decode the messages.
  /// default to [JsonMessageCodec]
  ServerAwarenessPlugin({
    MessageCodec<Message>? codec,
  })  : _documentAwareness = {},
        messageCodec = codec ??
            JsonMessageCodec(
              toJson: (message) => message.toJson(),
              fromJson: AwarenessMessage.fromJson,
            ),
        _awarenessController =
            StreamController<ServerAwarenessEvent>.broadcast();

  @override
  String get name => 'awareness';

  final Map<String, DocumentAwareness> _documentAwareness;
  final StreamController<ServerAwarenessEvent> _awarenessController;

  @override
  final MessageCodec<Message> messageCodec;

  @override
  void onMessage(ClientSession session, Message message) {
    if (message is! AwarenessMessage) {
      return;
    }

    switch (message.type) {
      case AwarenessMessageType.awarenessUpdate:
        _handleAwarenessUpdate(
          session,
          message as AwarenessUpdateMessage,
        );
        return;
      case AwarenessMessageType.awarenessQuery:
        _handleAwarenessQuery(
          session,
          message as AwarenessQueryMessage,
        );
        return;

      case AwarenessMessageType.awarenessState:
        return;
    }
  }

  /// handle the awareness update message
  void _handleAwarenessUpdate(
    ClientSession session,
    AwarenessUpdateMessage message,
  ) {
    final awareness = _documentAwareness[message.documentId];
    if (awareness == null) {
      return;
    }

    final oldState = awareness.states[message.state.clientId];
    if (oldState != null && oldState.lastUpdate >= message.state.lastUpdate) {
      return;
    }

    _documentAwareness[message.documentId] =
        awareness.copyWithUpdatedClient(message.state);

    _broadcastAwarenessUpdate(
      message.documentId,
      message.state.clientId,
      excludeClientIds: [session.id],
    );
    _updateController(
      ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientUpdated,
        documentId: message.documentId,
        clientId: message.state.clientId,
      ),
    );
  }

  /// handle the awareness query message
  void _handleAwarenessQuery(
    ClientSession session,
    AwarenessQueryMessage message,
  ) {
    _sendAwarenessStateToClient(message.documentId, session.id);
  }

  @override
  void onNewSession(ClientSession session) {
    return;
  }

  @override
  void onSessionClosed(ClientSession session) {
    final documentIds = _documentAwareness.keys.toList();
    for (final documentId in documentIds) {
      final awareness = _documentAwareness[documentId]!;
      if (awareness.states.containsKey(session.id)) {
        _documentAwareness[documentId] =
            awareness.copyWithRemovedClient(session.id);

        _broadcastAwarenessState(documentId);

        _updateController(
          ServerAwarenessEvent(
            type: ServerAwarenessEventType.clientLeft,
            documentId: documentId,
            clientId: session.id,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _documentAwareness.clear();
    _awarenessController.close();
  }

  /// broadcast the **full** awareness state to all clients
  Future<void> _broadcastAwarenessState(
    String documentId, {
    List<String> excludeClientIds = const [],
  }) async {
    final awareness = _documentAwareness[documentId];
    if (awareness == null) {
      return;
    }

    await server.broadcastMessage(
      AwarenessStateMessage(
        awareness: awareness,
        documentId: documentId,
      ),
      excludeClientIds: excludeClientIds,
    );
  }

  /// send the awareness state to a specific client
  Future<void> _sendAwarenessStateToClient(
    String documentId,
    String clientId,
  ) async {
    final awareness = _documentAwareness[documentId];
    if (awareness == null) {
      return;
    }

    await server.sendMessageToClient(
      clientId,
      AwarenessStateMessage(
        awareness: awareness,
        documentId: documentId,
      ),
    );
  }

  /// broadcast the awareness update to all clients
  Future<void> _broadcastAwarenessUpdate(
    String documentId,
    String clientId, {
    List<String> excludeClientIds = const [],
  }) async {
    final awareness = _documentAwareness[documentId];
    if (awareness == null) {
      return;
    }

    final client = awareness.states[clientId];
    if (client == null) {
      return;
    }

    await server.broadcastMessage(
      AwarenessUpdateMessage(
        documentId: documentId,
        state: client,
      ),
      excludeClientIds: excludeClientIds,
    );
  }

  @override
  void onDocumentRegistered(ClientSession session, String documentId) {
    var awareness = _documentAwareness[documentId] ??
        DocumentAwareness(
          documentId: documentId,
          states: {},
        );
    final client = ClientAwareness(
      clientId: session.id,
      metadata: {},
      lastUpdate: DateTime.now().millisecondsSinceEpoch,
    );

    awareness = awareness.copyWithUpdatedClient(client);

    _documentAwareness[documentId] = awareness;

    // send to all clients except the one that joined
    // the new incoming data
    _broadcastAwarenessUpdate(
      documentId,
      session.id,
      excludeClientIds: [session.id],
    );
    _sendAwarenessStateToClient(
      documentId,
      session.id,
    );

    _updateController(
      ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: session.id,
      ),
    );
  }

  void _updateController(ServerAwarenessEvent awareness) {
    assert(
      !_awarenessController.isClosed,
      '[ServerAwarenessPlugin] Cannot add new awareness events'
      ' after the plugin has been disposed',
    );
    if (_awarenessController.isClosed) {
      return;
    }
    _awarenessController.add(awareness);
  }
}
