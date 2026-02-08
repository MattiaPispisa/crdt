import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// Abstract class for operations
abstract class Operation {
  /// Constructor that initializes an operation
  const Operation({
    required this.type,
    required this.id,
  });

  /// The type of the operation
  final OperationType type;

  /// The ID of the handler that owns the operation
  final String id;

  /// Encodes the operation as bytes.
  ///
  /// This is the representation used inside [Change] to optimize memory usage.
  Uint8List toBytes() {
    final body = toBodyBytes();
    return OperationEnvelopeCodec.encode(
      handlerType: type.handler,
      handlerId: id,
      kind: type.kind,
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
    };
  }
}
