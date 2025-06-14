import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';

/// Awareness message types
enum AwarenessMessageType implements MessageTypeValue {
  /// message to update the awareness state
  awarenessUpdate(100),

  /// message to query the awareness state
  awarenessQuery(101),

  /// response message with the awareness state
  awarenessState(102);

  const AwarenessMessageType(this.value);

  @override
  final int value;
}

/// base class for awareness messages
abstract class AwarenessMessage extends Message {
  /// constructor
  const AwarenessMessage(super.type, super.documentId);

  /// from json
  static Message? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as int;
    if (type < 100 || type > 102) {
      return null;
    }

    switch (AwarenessMessageType.values[type - 100]) {
      case AwarenessMessageType.awarenessUpdate:
        return AwarenessUpdateMessage.fromJson(json);
      case AwarenessMessageType.awarenessQuery:
        return AwarenessQueryMessage.fromJson(json);
      case AwarenessMessageType.awarenessState:
        return AwarenessStateMessage.fromJson(json);
    }
  }
}

/// message to update the awareness state
class AwarenessUpdateMessage extends AwarenessMessage {
  /// constructor
  const AwarenessUpdateMessage({
    required this.state,
    required String documentId,
  }) : super(AwarenessMessageType.awarenessUpdate, documentId);

  /// from json
  factory AwarenessUpdateMessage.fromJson(Map<String, dynamic> json) =>
      AwarenessUpdateMessage(
        state: ClientAwareness.fromJson(json['state'] as Map<String, dynamic>),
        documentId: json['documentId'] as String,
      );

  /// client awareness state
  final ClientAwareness state;

  @override
  Map<String, dynamic> toJson() => {
        'type': type.value,
        'documentId': documentId,
        'state': state.toJson(),
      };

  @override
  String toString() =>
      'AwarenessUpdateMessage(state: $state, documentId: $documentId)';
}

/// message to query the awareness state
class AwarenessQueryMessage extends AwarenessMessage {
  /// constructor
  const AwarenessQueryMessage({
    required String documentId,
  }) : super(AwarenessMessageType.awarenessQuery, documentId);

  /// from json
  factory AwarenessQueryMessage.fromJson(Map<String, dynamic> json) =>
      AwarenessQueryMessage(
        documentId: json['documentId'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': type.value,
        'documentId': documentId,
      };

  @override
  String toString() => 'AwarenessQueryMessage(documentId: $documentId)';
}

/// message with the awareness state
class AwarenessStateMessage extends AwarenessMessage {
  /// constructor
  const AwarenessStateMessage({
    required this.awareness,
    required String documentId,
  }) : super(AwarenessMessageType.awarenessState, documentId);

  /// from json
  factory AwarenessStateMessage.fromJson(Map<String, dynamic> json) =>
      AwarenessStateMessage(
        awareness: DocumentAwareness.fromJson(
          json['awareness'] as Map<String, dynamic>,
        ),
        documentId: json['documentId'] as String,
      );

  /// document awareness state
  final DocumentAwareness awareness;

  @override
  Map<String, dynamic> toJson() => {
        'type': type.value,
        'documentId': documentId,
        'awareness': awareness.toJson(),
      };

  @override
  String toString() =>
      'AwarenessStateMessage(awareness: $awareness, documentId: $documentId)';
}
