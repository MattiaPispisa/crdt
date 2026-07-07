import 'dart:async';

import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/plugins/awareness/client/throttle.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';

/// Client awareness plugin
///
/// This plugin is used to manage the awareness of the clients
/// connected to the same document
class ClientAwarenessPlugin extends ClientSyncPlugin {
  /// Constructor
  ///
  /// [initialMetadata] is the initial metadata of the client
  /// sent to the server [onConnected]
  ///
  /// [codec] is the codec to use to encode and decode the messages.
  /// default to [JsonMessageCodec]
  ///
  /// [throttleDuration] is the duration to wait before sending the awareness
  /// update to the server. default to 50 milliseconds
  ClientAwarenessPlugin({
    MessageCodec<Message>? codec,
    Map<String, dynamic>? initialMetadata,
    Duration throttleDuration = const Duration(milliseconds: 50),
  })  : messageCodec = codec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: AwarenessMessage.fromJson,
            ),
        _initialMetadata = initialMetadata,
        _awarenessController = StreamController<DocumentAwareness>.broadcast(),
        _throttler = Throttler(throttleDuration);

  @override
  String get name => 'awareness';

  DocumentAwareness? _awareness;

  /// The awareness state of the client
  ClientAwareness? get myState => _awareness?.states[client.sessionId];

  final StreamController<DocumentAwareness> _awarenessController;

  /// Stream of awareness state changes
  Stream<DocumentAwareness> get awarenessStream => _awarenessController.stream;

  /// The awareness state of the client
  DocumentAwareness get awareness =>
      _awareness ??
      DocumentAwareness(
        documentId: client.document.documentId,
        states: {},
      );

  /// Initial metadata
  final Map<String, dynamic>? _initialMetadata;

  @override
  final MessageCodec<Message> messageCodec;

  final Throttler _throttler;

  @override
  void onMessage(Message message) {
    if (message is! AwarenessMessage) {
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

  /// Updates document awareness with the authoritative server state.
  ///
  /// The server state is authoritative for every remote client, but the local
  /// client is the source of truth for its own presence. A full state message
  /// can predate a just-applied local update, so the local client's own entry
  /// is overlaid on top of the server state to avoid clobbering it.
  void _handleAwarenessState(AwarenessStateMessage message) {
    final sessionId = client.sessionId;
    final localOwnState =
        sessionId != null ? _awareness?.states[sessionId] : null;

    var next = message.awareness;
    if (localOwnState != null) {
      next = next.copyWithUpdatedClient(localOwnState);
    }

    _awareness = next;
    _updateController(_awareness!);
  }

  /// Updates client awareness state received from the server
  void _handleAwarenessUpdate(AwarenessUpdateMessage message) {
    if (_awareness != null) {
      _awareness = _awareness!.copyWithUpdatedClient(message.state);
      _updateController(_awareness!);
    }
  }

  /// Update the local state of the awareness then send the update to the server
  void updateLocalState(
    Map<String, dynamic> metadata,
  ) {
    return _internalUpdateLocalState(
      metadata,
      throttle: true,
    );
  }

  void _internalUpdateLocalState(
    Map<String, dynamic> metadata, {
    required bool throttle,
  }) {
    final sessionId = client.sessionId;
    if (sessionId == null) {
      return;
    }

    final currentMetadata = _awareness?.states[sessionId]?.metadata;

    final state = ClientAwareness(
      clientId: sessionId,
      metadata: {
        ...currentMetadata ?? {},
        ...metadata,
      },
    );

    _awareness = (_awareness ??
            DocumentAwareness(
              documentId: client.document.documentId,
              states: {},
            ))
        .copyWithUpdatedClient(state);

    _updateController(_awareness!);

    void send() => client.sendMessage(
          AwarenessUpdateMessage(
            state: state,
            documentId: client.document.documentId,
          ),
        );

    if (throttle) {
      _throttler(send);
    } else {
      send();
    }
  }

  /// Request the state of the awareness from the server
  void requestState(String documentId) {
    client.sendMessage(
      AwarenessQueryMessage(
        documentId: documentId,
      ),
    );
  }

  @override
  void onConnected() {
    final sessionId = client.sessionId;
    final metadata = _initialMetadata;
    if (sessionId == null || metadata == null) {
      return;
    }

    _internalUpdateLocalState(metadata, throttle: false);
    return;
  }

  @override
  void onDisconnected() {
    // server is aware of client leaving so we don't need to do anything
    return;
  }

  @override
  void dispose() {
    _throttler.dispose();
    _awarenessController.close();
  }

  void _updateController(DocumentAwareness awareness) {
    assert(
      !_awarenessController.isClosed,
      '[ClientAwarenessPlugin] Cannot update the awareness state'
      ' after the plugin has been disposed',
    );
    if (_awarenessController.isClosed) {
      return;
    }
    _awarenessController.add(awareness);
  }
}
