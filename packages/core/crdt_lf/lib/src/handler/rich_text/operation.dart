part of 'handler.dart';

/// Sets one mark type over a range of characters.
///
/// The operation is stamped, and the stamp is what decides the winner where
/// several marks of one type cover the same character. It is never trimmed
/// against the marks already there: the range it names is the range the author
/// asked for, and the formatting anyone sees is worked out from all of them.
///
/// Layout:
/// - `start:` [MarkAnchor] bytes
/// - `end:` [MarkAnchor] bytes
/// - `typeLen:` uvarint
/// - `type:` utf8 bytes
/// - `hasValue:` u8 — 0 when the mark removes [Mark.type], 1 otherwise
/// - if `hasValue == 1`:
///   - `valueLen:` uvarint
///   - `value:` bytes, encoded by the handler's value codec
class _RichTextMarkOperation extends Operation {
  _RichTextMarkOperation({
    required this.mark,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  /// Creates a mark operation addressed to [handler].
  factory _RichTextMarkOperation.fromHandler(
    CRDTRichTextHandler handler, {
    required Mark mark,
  }) {
    return _RichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      valueCodec: handler.valueCodec,
      mark: mark,
    );
  }

  /// Decodes a mark operation body addressed to [handler].
  factory _RichTextMarkOperation.fromBodyBytes(
    CRDTRichTextHandler handler,
    Uint8List body,
  ) {
    var offset = 0;

    final startRec = MarkAnchor.readFromBytes(body, offset: offset);
    offset = startRec.nextOffset;

    final endRec = MarkAnchor.readFromBytes(body, offset: offset);
    offset = endRec.nextOffset;

    final typeRec = UVarint.readBytes(
      body,
      offset: offset,
      what: 'rich text mark type',
    );
    offset = typeRec.nextOffset;

    if (offset >= body.length) {
      throw const FormatException('Truncated rich text mark');
    }
    final hasValue = body[offset];
    offset += 1;
    if (hasValue > 1) {
      throw FormatException('Invalid rich text mark value flag: $hasValue');
    }

    Object? value;
    if (hasValue == 1) {
      final valueRec = UVarint.readBytes(
        body,
        offset: offset,
        what: 'rich text mark value',
      );
      value = handler.valueCodec.decode(valueRec.value);
    }

    return _RichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      valueCodec: handler.valueCodec,
      mark: Mark(
        start: startRec.value,
        end: endRec.value,
        type: utf8.decode(typeRec.value),
        value: value,
      ),
    );
  }

  /// What this operation sets, and over which range.
  final Mark mark;

  /// Turns [Mark.value] into bytes and back.
  final ValueCodec<Object?> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(mark.start.toBytes())
      ..add(mark.end.toBytes());
    UVarint.writeBytes(Uint8List.fromList(utf8.encode(mark.type)), out);
    final value = mark.value;
    if (value == null) {
      out.addByte(0);
      return out.toBytes();
    }
    out.addByte(1);
    UVarint.writeBytes(valueCodec.encode(value), out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'mark': mark.type,
      'value': mark.value,
      'start': mark.start.toString(),
      'end': mark.end.toString(),
    };
  }
}
