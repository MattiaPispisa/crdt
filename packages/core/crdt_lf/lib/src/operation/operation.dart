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

  OperationId? _stamp;

  /// The id of the change that carries this operation, and the mark a
  /// last-writer-wins handler orders it by; `null` before the document has
  /// minted one.
  ///
  /// Set by the document. A handler reads it, it never writes it. Whether a
  /// handler reads it at all is [OperationType.stamped].
  ///
  // It costs nothing on the wire: the change already carries its id, so a
  // stamped kind spends one bit in the envelope to declare itself and no
  // bytes to carry the value.
  OperationId? get stamp => _stamp;

  /// Assigns the id, once.
  ///
  /// Throws a [StateError] on a second write. A last-writer-wins handler
  /// stores this value **inside its state**, so an operation restamped after
  /// one peer folded it leaves the two peers holding different values.
  set stamp(OperationId? value) {
    if (_stamp != null) {
      throw StateError(
        'The stamp of ${type.toPayload()} is already set. It is minted once, '
        'by the document, and it ends up inside handler state: rewriting it '
        'leaves two peers holding different values.',
      );
    }
    _stamp = value;
  }

  /// Encodes the operation as bytes.
  ///
  /// This is the representation used inside [Change] to optimize memory usage.
  Uint8List toBytes() {
    final body = toBodyBytes();
    return OperationEnvelopeCodec.encode(
      handlerType: type.handler,
      handlerId: id,
      kind: type.kind,
      // The envelope declares whether the kind is stamped
      // and does not carry the stamp.
      stamped: type.stamped,
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
