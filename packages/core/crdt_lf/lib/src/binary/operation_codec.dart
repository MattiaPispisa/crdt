import 'dart:typed_data';
import 'package:crdt_lf/crdt_lf.dart';

/// Decoded operation envelope metadata.
class OperationEnvelope {
  /// Creates a new [OperationEnvelope] with the given properties.
  OperationEnvelope({
    required this.handlerType,
    required this.handlerId,
    required this.kind,
    required this.bodyOffset,
    this.stamped = false,
  });

  /// Handler runtime type string (as in [OperationType.handler]).
  final String handlerType;

  /// Handler instance id (as in [Operation.id]).
  final String handlerId;

  /// Operation kind, with the stamped flag already stripped.
  ///
  /// Only meaningful together with [handlerType]: the same value means
  /// different things for two different handlers.
  final int kind;

  /// Whether the peer that wrote this operation reads a stamp for its kind
  /// (see [OperationType.stamped]).
  ///
  /// The stamp itself is not here — it is the id of the change carrying the
  /// operation. This is the writer's declaration, and it is what a reader
  /// compares against its own to catch a disagreement about the kind.
  final bool stamped;

  /// Offset in the buffer where the body starts.
  final int bodyOffset;
}

/// Binary envelope for operations.
///
/// Format:
/// - handlerTypeLen: uvarint
/// - handlerType: utf8
/// - handlerIdLen: uvarint
/// - handlerId: utf8
/// - kind: u8, where bit 7 declares the kind stamped
/// - body: bytes
///
/// Bit 7 of the kind byte is what caps a kind at [OperationType.maxKind]. It
/// costs no bytes of its own: a stamped operation is marked here, and the
/// mark itself is the id of the change it travels in.
class OperationEnvelopeCodec {
  static const int _stampedFlag = 0x80;

  /// Writes the part of the envelope that identifies the handler:
  /// `[uvarint typeLen][type utf8][uvarint idLen][id utf8]`.
  ///
  /// [encode] starts with these bytes, and a handler matches a change by
  /// comparing them against the head of its payload without decoding it. Both
  /// go through here so the two can never drift apart.
  static void writeEnvelopePrefix(
    BytesBuilder out,
    String handlerType,
    String handlerId,
  ) {
    UVarint.writeString(handlerType, out);
    UVarint.writeString(handlerId, out);
  }

  /// Encodes an [OperationEnvelope] into a byte array.
  ///
  /// [stamped] sets bit 7 of the kind byte. It adds no bytes.
  ///
  /// Throws an [ArgumentError] when [kind] does not fit in the seven bits
  /// left by the stamped flag.
  static Uint8List encode({
    required String handlerType,
    required String handlerId,
    required int kind,
    required Uint8List body,
    bool stamped = false,
  }) {
    if (kind < 0 || kind > OperationType.maxKind) {
      throw ArgumentError.value(
        kind,
        'kind',
        'must be in 0..${OperationType.maxKind}, because bit 7 of the kind '
            'byte declares the kind stamped',
      );
    }

    final out = BytesBuilder(copy: false);
    writeEnvelopePrefix(out, handlerType, handlerId);
    out
      ..addByte(stamped ? kind | _stampedFlag : kind)
      ..add(body);

    return out.toBytes();
  }

  /// Decodes an [OperationEnvelope] from a byte array.
  ///
  /// Throws a [FormatException] on a buffer that ends inside the envelope.
  static OperationEnvelope decode(Uint8List bytes) {
    var offset = 0;

    final handlerTypeRecord = UVarint.readString(
      bytes,
      offset: offset,
      what: 'handlerType',
    );
    final handlerType = handlerTypeRecord.value;
    offset = handlerTypeRecord.nextOffset;

    final handlerIdRecord = UVarint.readString(
      bytes,
      offset: offset,
      what: 'handlerId',
    );
    final handlerId = handlerIdRecord.value;
    offset = handlerIdRecord.nextOffset;

    if (offset >= bytes.length) {
      throw const FormatException('Missing operation kind');
    }
    final rawKind = bytes[offset];
    offset += 1;

    return OperationEnvelope(
      handlerType: handlerType,
      handlerId: handlerId,
      kind: rawKind & OperationType.maxKind,
      stamped: rawKind & _stampedFlag != 0,
      bodyOffset: offset,
    );
  }
}
