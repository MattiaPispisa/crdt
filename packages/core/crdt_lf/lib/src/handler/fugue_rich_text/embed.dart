// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _Embed {
  _Embed(this.data, this.stamp);

  final Map<String, Object?> data;

  // The write that set [data]: the insert, then each update that won.
  final OperationId stamp;
}

// Tags 0-5 are the ones of `_MarkValue`; then 6 list (count, values), 7 map
// (count, then per entry the key as length + WTF-8 and the value), 8 bytes
// (length, bytes).
class _EmbedValue {
  static const int _list = 6;
  static const int _map = 7;
  static const int _bytes = 8;

  // Checked on read, so hostile bytes cannot overflow the stack, and on write,
  // so this peer never writes data the others refuse.
  static const int maxDepth = 16;

  // Checks [embed], then gives its bytes and the frozen data they decode to,
  // which is what the peers read.
  static ({Map<String, Object?> data, Uint8List bytes}) prepare(
    Map<String, Object?> embed,
    int? maxBytes,
  ) {
    _check(embed, 0);
    final bytes = encode(freezeEmbed(embed));
    if (maxBytes != null && bytes.length > maxBytes) {
      throw ArgumentError.value(
        embed,
        'embed',
        'takes ${bytes.length} bytes, more than maxEmbedBytes ($maxBytes)',
      );
    }
    return (data: readData(bytes, 0).data, bytes: bytes);
  }

  static void _check(Object? value, int depth) {
    switch (value) {
      case null || bool() || String() || Uint8List():
        return;
      case final List<Object?> list:
        _checkDepth(value, depth);
        for (final item in list) {
          _check(item, depth + 1);
        }
      case final Map<Object?, Object?> map:
        _checkDepth(value, depth);
        for (final value in map.values) {
          _check(value, depth + 1);
        }
      case final num number when _MarkValue._safeInt(number) != null:
        return;
      case final double number when number.isFinite:
        return;
      case int():
        throw ArgumentError.value(value, 'embed', 'out of the safe int range');
      case double():
        throw ArgumentError.value(value, 'embed', 'must be a finite double');
      default:
        throw ArgumentError.value(
          value,
          'embed',
          'must be null, bool, int, double, String, Uint8List, List or Map',
        );
    }
  }

  static void _checkDepth(Object value, int depth) {
    if (depth >= maxDepth) {
      throw ArgumentError.value(
        value,
        'embed',
        'nested deeper than $maxDepth levels',
      );
    }
  }

  static Uint8List encode(Map<String, Object?> data) {
    final out = BytesBuilder(copy: false);
    _write(data, out);
    return out.toBytes();
  }

  static void _write(Object? value, BytesBuilder out) {
    switch (value) {
      case final Uint8List bytes:
        out.addByte(_bytes);
        UVarint.writeBytes(bytes, out);
      case final List<Object?> list:
        out.addByte(_list);
        UVarint.write(list.length, out);
        for (final item in list) {
          _write(item, out);
        }
      case final Map<Object?, Object?> map:
        out.addByte(_map);
        UVarint.write(map.length, out);
        for (final entry in map.entries) {
          UVarint.writeBytes(Wtf8.encode(entry.key! as String), out);
          _write(entry.value, out);
        }
      default:
        _MarkValue.write(value, out);
    }
  }

  static ({Map<String, Object?> data, int nextOffset}) readData(
    Uint8List bytes,
    int offset,
  ) {
    if (offset < bytes.length && bytes[offset] != _map) {
      throw FormatException('Embed data has tag ${bytes[offset]}, not a map');
    }
    final read = _read(bytes, offset, 0);
    return (
      data: freezeEmbed(read.value! as Map<String, Object?>),
      nextOffset: read.nextOffset,
    );
  }

  static ({Object? value, int nextOffset}) _read(
    Uint8List bytes,
    int offset,
    int depth,
  ) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated embed value');
    }
    final tag = bytes[offset];
    var cursor = offset + 1;
    switch (tag) {
      case _bytes:
        final rec =
            UVarint.readBytes(bytes, offset: cursor, what: 'embed bytes');
        return (
          value: Uint8List.fromList(rec.value),
          nextOffset: rec.nextOffset
        );
      case _list:
        _readDepth(depth);
        final count = UVarint.read(bytes, offset: cursor);
        cursor = count.nextOffset;
        final list = <Object?>[];
        for (var i = 0; i < count.value; i++) {
          final item = _read(bytes, cursor, depth + 1);
          list.add(item.value);
          cursor = item.nextOffset;
        }
        return (value: list, nextOffset: cursor);
      case _map:
        _readDepth(depth);
        final count = UVarint.read(bytes, offset: cursor);
        cursor = count.nextOffset;
        final map = <String, Object?>{};
        for (var i = 0; i < count.value; i++) {
          final key =
              UVarint.readBytes(bytes, offset: cursor, what: 'embed key');
          final item = _read(bytes, key.nextOffset, depth + 1);
          map[Wtf8.decode(key.value)] = item.value;
          cursor = item.nextOffset;
        }
        return (value: map, nextOffset: cursor);
      case > _bytes:
        throw FormatException('Unknown embed value tag $tag');
      default:
        return _MarkValue.read(bytes, offset);
    }
  }

  static void _readDepth(int depth) {
    if (depth >= maxDepth) {
      throw const FormatException('Embed nested deeper than $maxDepth levels');
    }
  }
}

// Layout: tag, liveCount: uvarint, then per live embed: id, stamp, data.
// Written only when an embed is live, so a blob without embeds keeps its
// bytes. Sorted by id: `mergeSnapshot` needs equal states to give equal bytes.
class _EmbedSection {
  static const int tag = 1;

  static void write(_EmbedTable embeds, BytesBuilder out) {
    if (embeds.live.isEmpty) {
      return;
    }
    out.addByte(tag);
    final live = embeds.live.keys.toList()..sort((a, b) => a.compareTo(b));
    UVarint.write(live.length, out);
    for (final id in live) {
      final embed = embeds.live[id]!;
      out
        ..add(id.toBytes())
        ..add(embed.stamp.toUint8List())
        ..add(_EmbedValue.encode(embed.data));
    }
  }

  static ({_EmbedTable embeds, int nextOffset}) read(
    Uint8List bytes,
    int offset,
  ) {
    final embeds = _EmbedTable();
    if (offset == bytes.length) {
      return (embeds: embeds, nextOffset: offset);
    }
    if (bytes[offset] != tag) {
      throw FormatException('Unknown rich text embeds tag ${bytes[offset]}');
    }
    final liveCount = UVarint.read(bytes, offset: offset + 1);
    var cursor = liveCount.nextOffset;
    for (var i = 0; i < liveCount.value; i++) {
      final id = FugueElementID.readFromBytes(bytes, offset: cursor);
      final stamp = OperationId.readFromBytes(bytes, offset: id.nextOffset);
      final data = _EmbedValue.readData(
        bytes,
        id.nextOffset + OperationId.byteLength,
      );
      embeds.live[id.value] = _Embed(data.data, stamp);
      cursor = data.nextOffset;
    }
    return (embeds: embeds, nextOffset: cursor);
  }
}

// Kind 5. A text insert of one U+FFFC element, so the Fugue paths for apply,
// undo and element ids take it as it is. Not stamped: ids are never reused.
class _FugueRichTextEmbedOperation extends FugueTextInsertOperation {
  _FugueRichTextEmbedOperation({
    required super.leftOrigin,
    required super.rightOrigin,
    required FugueElementID element,
    required this.data,
    required super.id,
    required super.type,
    Uint8List? dataBytes,
  })  : _dataBytes = dataBytes,
        super(
          items: [
            FugueTextInsertItem(
              id: element,
              text: RichTextSpan.objectReplacement,
            ),
          ],
        );

  // Layout: leftOrigin, rightOrigin, element id, data.
  factory _FugueRichTextEmbedOperation.fromBodyBytes(
    CRDTFugueRichTextHandler handler,
    Uint8List body,
  ) {
    final left = FugueElementID.readFromBytes(body);
    final right = FugueElementID.readFromBytes(body, offset: left.nextOffset);
    final element =
        FugueElementID.readFromBytes(body, offset: right.nextOffset);
    final data = _EmbedValue.readData(body, element.nextOffset);
    return _FugueRichTextEmbedOperation(
      id: handler.id,
      type: handler._embedType,
      leftOrigin: left.value,
      rightOrigin: right.value,
      element: element.value,
      data: data.data,
    );
  }

  final Map<String, Object?> data;

  Uint8List? _dataBytes;

  FugueElementID get element => items.single.id;

  @override
  Uint8List toBodyBytes() => (BytesBuilder(copy: false)
        ..add(leftOrigin.toBytes())
        ..add(rightOrigin.toBytes())
        ..add(element.toBytes())
        ..add(_dataBytes ??= _EmbedValue.encode(data)))
      .toBytes();
}

// Kind 6, stamped: the newest update of an embed wins.
class _FugueRichTextEmbedUpdateOperation extends Operation {
  _FugueRichTextEmbedUpdateOperation({
    required this.element,
    required this.data,
    required super.id,
    required super.type,
    Uint8List? dataBytes,
  }) : _dataBytes = dataBytes;

  // Layout: element id, data.
  factory _FugueRichTextEmbedUpdateOperation.fromBodyBytes(
    CRDTFugueRichTextHandler handler,
    Uint8List body,
  ) {
    final element = FugueElementID.readFromBytes(body);
    final data = _EmbedValue.readData(body, element.nextOffset);
    return _FugueRichTextEmbedUpdateOperation(
      id: handler.id,
      type: handler._embedUpdateType,
      element: element.value,
      data: data.data,
    );
  }

  final FugueElementID element;
  final Map<String, Object?> data;

  Uint8List? _dataBytes;

  @override
  Uint8List toBodyBytes() => (BytesBuilder(copy: false)
        ..add(element.toBytes())
        ..add(_dataBytes ??= _EmbedValue.encode(data)))
      .toBytes();
}
