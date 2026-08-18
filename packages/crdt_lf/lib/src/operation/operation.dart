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

  /// The stamp of this operation; `null` when its kind is not stamped
  /// (see [OperationType.stamped]).
  ///
  /// Set by the document, in `registerOperation` for a local operation and
  /// from the envelope for one that arrived from another peer. A handler
  /// reads it, it never writes it.
  OperationId? get stamp => _stamp;

  /// Assigns the stamp, once.
  ///
  /// A second write throws. The stamp is what a last-writer-wins handler
  /// stores **inside its state**, so an operation whose stamp changed after
  /// one peer folded it leaves the two peers holding different values, with
  /// nothing to show for it. There is no case where the same operation is
  /// legitimately stamped twice: a local one is minted in `registerOperation`,
  /// a remote one is read off the envelope, and a compound is a fresh
  /// operation.
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
