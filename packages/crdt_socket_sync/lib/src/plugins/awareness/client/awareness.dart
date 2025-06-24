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

  final StreamController<DocumentAwareness> _awarenessController;

  /// Stream of awareness state changes
  Stream<DocumentAwareness> get awarenessStream => _awarenessController.stream;

  /// The awareness state of the client
  DocumentAwareness get awareness =>
      _awareness ??
      DocumentAwareness(
        documentId: client.document.peerId.toString(),
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

  void _handleAwarenessState(AwarenessStateMessage message) {
    final localState = _awareness?.states[client.sessionId];
    final remoteState = message.awareness.states[client.sessionId];

    _awareness = message.awareness;

    // verify if the local state is up to date
    if (localState != null &&
        remoteState != null &&
        localState.lastUpdate >= remoteState.lastUpdate) {
      if (_awareness != null) {
        _awareness = _awareness!.copyWithUpdatedClient(localState);
        _updateController(_awareness!);
      }
      return;
    }
  }

  void _handleAwarenessUpdate(AwarenessUpdateMessage message) {
    final localStateId = client.sessionId;
    final clientAwareness = _awareness?.states[message.state.clientId];

    // verify if the local state is up to date
    if (localStateId == message.state.clientId &&
        clientAwareness != null &&
        clientAwareness.lastUpdate >= message.state.lastUpdate) {
      return;
    }
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

    final state = ClientAwareness(
      clientId: sessionId,
      metadata: metadata,
      lastUpdate: DateTime.now().millisecondsSinceEpoch,
    );

    final documentId = client.document.peerId.toString();

    _awareness = (_awareness ??
            DocumentAwareness(
              documentId: documentId,
              states: {},
            ))
        .copyWithUpdatedClient(state);

    _updateController(_awareness!);

    void send() => client.sendMessage(
          AwarenessUpdateMessage(
            state: state,
            documentId: documentId,
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
