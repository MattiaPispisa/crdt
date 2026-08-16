import 'dart:convert';
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
    this.stamp,
  });

  /// Handler runtime type string (as in [OperationType.handler]).
  final String handlerType;

  /// Handler instance id (as in [Operation.id]).
  final String handlerId;

  /// Operation kind, with the stamp flag already stripped.
  ///
  /// Only meaningful together with [handlerType]: the same value means
  /// different things for two different handlers.
  final int kind;

  /// The stamp the writer minted for this operation; `null` when the handler
  /// does not ask to be stamped.
  final OperationStamp? stamp;

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
/// - kind: u8, where bit 7 signals that a stamp follows
/// - stamp: [OperationStamp.byteLength] bytes, only when bit 7 is set
/// - body: bytes
///
/// The stamp sits here rather than in the body for three reasons. It is a
/// fact about the framework, not about what the handler means, so it belongs
/// to the part of the format the framework owns. It is written the same way
/// for every handler, so a tool can read it without knowing which handler
/// produced the operation. And it reaches the handler attached to the
/// operation, which keeps `applyOperation` free of the change that carried
/// it.
///
/// Bit 7 of the kind byte is what caps a kind at [OperationType.maxKind].
class OperationEnvelopeCodec {
  static const int _stampFlag = 0x80;

  /// Encodes an [OperationEnvelope] into a byte array.
  ///
  /// Passing a [stamp] sets bit 7 of the kind byte and writes the stamp right
  /// after it. Leaving it out produces the same bytes as a build that knows
  /// nothing about stamps.
  ///
  /// Throws an [ArgumentError] when [kind] does not fit in the seven bits
  /// left by the stamp flag.
  static Uint8List encode({
    required String handlerType,
    required String handlerId,
    required int kind,
    required Uint8List body,
    OperationStamp? stamp,
  }) {
    if (kind < 0 || kind > OperationType.maxKind) {
      throw ArgumentError.value(
        kind,
        'kind',
        'must be in 0..${OperationType.maxKind}, because bit 7 of the kind '
            'byte signals the presence of a stamp',
      );
    }

    final out = BytesBuilder(copy: false);

    final handlerTypeBytes = utf8.encode(handlerType);
    UVarint.write(handlerTypeBytes.length, out);
    out.add(handlerTypeBytes);

    final handlerIdBytes = utf8.encode(handlerId);
    UVarint.write(handlerIdBytes.length, out);
    out
      ..add(handlerIdBytes)
      ..addByte(stamp == null ? kind : kind | _stampFlag);

    if (stamp != null) {
      out.add(stamp.toUint8List());
    }

    out.add(body);

    return out.toBytes();
  }

  /// Decodes an [OperationEnvelope] from a byte array.
  ///
  /// Throws a [FormatException] on a buffer that ends inside the envelope,
  /// including one that flags a stamp and then stops short of it.
  static OperationEnvelope decode(Uint8List bytes) {
    var offset = 0;

    final handlerTypeLenRec = UVarint.read(bytes, offset: offset);
    final handlerTypeLen = handlerTypeLenRec.value;
    offset = handlerTypeLenRec.nextOffset;
    final handlerTypeEnd = offset + handlerTypeLen;
    if (handlerTypeEnd > bytes.length) {
      throw const FormatException('Truncated handlerType');
    }
    final handlerType = utf8.decode(
      Uint8List.sublistView(bytes, offset, handlerTypeEnd),
    );
    offset = handlerTypeEnd;

    final handlerIdLenRec = UVarint.read(bytes, offset: offset);
    final handlerIdLen = handlerIdLenRec.value;
    offset = handlerIdLenRec.nextOffset;
    final handlerIdEnd = offset + handlerIdLen;
    if (handlerIdEnd > bytes.length) {
      throw const FormatException('Truncated handlerId');
    }
    final handlerId = utf8.decode(
      Uint8List.sublistView(bytes, offset, handlerIdEnd),
    );
    offset = handlerIdEnd;

    if (offset >= bytes.length) {
      throw const FormatException('Missing operation kind');
    }
    final rawKind = bytes[offset];
    offset += 1;

    OperationStamp? stamp;
    if (rawKind & _stampFlag != 0) {
      stamp = OperationStamp.fromUint8List(bytes, offset: offset);
      offset += OperationStamp.byteLength;
    }

    return OperationEnvelope(
      handlerType: handlerType,
      handlerId: handlerId,
      kind: rawKind & OperationType.maxKind,
      stamp: stamp,
      bodyOffset: offset,
    );
  }
}
