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
  });

  /// Handler runtime type string (as in [OperationType.handler]).
  final String handlerType;

  /// Handler instance id (as in [Operation.id]).
  final String handlerId;

  /// Operation kind (insert/delete/update).
  final int kind;

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
/// - kind: u8
/// - body: bytes
class OperationEnvelopeCodec {
  OperationEnvelopeCodec._();

  /// Encodes an [OperationEnvelope] into a byte array.
  static Uint8List encode({
    required String handlerType,
    required String handlerId,
    required int kind,
    required Uint8List body,
  }) {
    final out = BytesBuilder(copy: false);

    final handlerTypeBytes = utf8.encode(handlerType);
    UVarint.write(handlerTypeBytes.length, out);
    out.add(handlerTypeBytes);

    final handlerIdBytes = utf8.encode(handlerId);
    UVarint.write(handlerIdBytes.length, out);
    out
      ..add(handlerIdBytes)
      ..addByte(kind & 0xFF)
      ..add(body);

    return out.toBytes();
  }

  /// Decodes an [OperationEnvelope] from a byte array.
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
    final kind = bytes[offset];
    offset += 1;

    return OperationEnvelope(
      handlerType: handlerType,
      handlerId: handlerId,
      kind: kind,
      bodyOffset: offset,
    );
  }
}
