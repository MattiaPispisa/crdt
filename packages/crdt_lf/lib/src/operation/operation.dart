import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// Abstract class for operations
abstract class Operation {
  /// Constructor that initializes an operation
  Operation({
    required this.type,
    required this.id,
  });

  /// The type of the operation
  final OperationType type;

  /// The ID of the handler that owns the operation
  final String id;

  /// The last-writer-wins stamp of this operation; `null` when the handler
  /// that owns it does not ask to be stamped.
  ///
  /// Set by the document, in `registerOperation` for a local operation and
  /// from the envelope for one that arrived from another peer. A handler
  /// reads it, it never writes it.
  OperationStamp? stamp;

  /// Encodes the operation as bytes.
  ///
  /// This is the representation used inside [Change] to optimize memory usage.
  Uint8List toBytes() {
    final body = toBodyBytes();
    return OperationEnvelopeCodec.encode(
      handlerType: type.handler,
      handlerId: id,
      kind: type.kind,
      stamp: stamp,
      body: body,
    );
  }

  /// Encodes the operation body bytes (without the envelope).
  Uint8List toBodyBytes();

  /// Converts the operation to a payload
  Map<String, dynamic> toPayload() {
    return {
      'id': id,
      'type': type.toPayload(),
      if (stamp != null) 'stamp': stamp.toString(),
    };
  }
}
