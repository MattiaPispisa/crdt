// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _Anchor {
  _Anchor(this.side, FugueElementID this.id);

  const _Anchor.text()
      : side = sentinel,
        id = null;

  static ({_Anchor anchor, int nextOffset}) read(Uint8List bytes, int offset) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated rich text anchor');
    }
    final side = bytes[offset];
    if (side == sentinel) {
      return (anchor: const _Anchor.text(), nextOffset: offset + 1);
    }
    if (side != before && side != after) {
      throw FormatException('Unknown rich text anchor side $side');
    }
    final idRec = FugueElementID.readFromBytes(bytes, offset: offset + 1);
    return (anchor: _Anchor(side, idRec.value), nextOffset: idRec.nextOffset);
  }

  static const int before = 0;
  static const int after = 1;
  static const int sentinel = 2;

  final int side;
  final FugueElementID? id;

  void write(BytesBuilder out) {
    out.addByte(side);
    if (side != sentinel) {
      out.add(id!.toBytes());
    }
  }

  // The first live index the slot precedes, or null for an unknown element.
  int? _liveSlot(FugueTree<String> tree) {
    final id = this.id!;
    final after = tree.liveIndexAfter(id);
    if (after == null) {
      return null;
    }
    if (side == before && tree.isLive(id)) {
      return after - 1;
    }
    return after;
  }

  int? liveStart(FugueTree<String> tree) =>
      side == sentinel ? 0 : _liveSlot(tree);

  int? liveEnd(FugueTree<String> tree, int length) =>
      side == sentinel ? length : _liveSlot(tree);

  @override
  bool operator ==(Object other) =>
      other is _Anchor && other.side == side && other.id == id;

  @override
  int get hashCode => Object.hash(side, id);
}

class _Mark {
  _Mark({
    required this.stamp,
    required this.key,
    required this.value,
    required this.start,
    required this.end,
  });

  final OperationId stamp;
  final String key;
  final Object? value;
  final _Anchor start;
  final _Anchor end;

  static int byStamp(_Mark a, _Mark b) => a.stamp.compareTo(b.stamp);
}

// Layout: key, value, start anchor, end anchor.
class _MarkBody {
  static void write(
    BytesBuilder out, {
    required String key,
    required Object? value,
    required _Anchor start,
    required _Anchor end,
  }) {
    UVarint.writeBytes(Wtf8.encode(key), out);
    _MarkValue.write(value, out);
    start.write(out);
    end.write(out);
  }

  static ({
    String key,
    Object? value,
    _Anchor start,
    _Anchor end,
    int nextOffset,
  }) read(Uint8List bytes, int offset) {
    final keyRec = UVarint.readBytes(bytes, offset: offset, what: 'mark key');
    final valueRec = _MarkValue.read(bytes, keyRec.nextOffset);
    final start = _Anchor.read(bytes, valueRec.nextOffset);
    final end = _Anchor.read(bytes, start.nextOffset);
    return (
      key: Wtf8.decode(keyRec.value),
      value: valueRec.value,
      start: start.anchor,
      end: end.anchor,
      nextOffset: end.nextOffset,
    );
  }
}

class _MarkValue {
  static const int _null = 0;
  static const int _false = 1;
  static const int _true = 2;
  static const int _int = 3;
  static const int _double = 4;
  static const int _string = 5;

  // Zigzag doubles the magnitude, and the result must stay a safe JavaScript
  // integer (2^53 - 1) so every platform reads the same int.
  static const int _maxSafeInt = 4503599627370495;

  static void check(Object? value) {
    if (value == null || value is bool || value is String) {
      return;
    }
    if (value is int) {
      if (value > _maxSafeInt || value < -_maxSafeInt) {
        throw ArgumentError.value(value, 'value', 'out of the safe int range');
      }
      return;
    }
    if (value is double) {
      return;
    }
    throw ArgumentError.value(
      value,
      'value',
      'must be null, bool, int, double or String',
    );
  }

  static void write(Object? value, BytesBuilder out) {
    switch (value) {
      case null:
        out.addByte(_null);
      case false:
        out.addByte(_false);
      case true:
        out.addByte(_true);
      case final int v:
        out.addByte(_int);
        UVarint.write(v >= 0 ? v * 2 : -v * 2 - 1, out);
      case final double v:
        out
          ..addByte(_double)
          ..add((ByteData(8)..setFloat64(0, v)).buffer.asUint8List());
      case final String v:
        out.addByte(_string);
        UVarint.writeBytes(Wtf8.encode(v), out);
      default:
        check(value);
    }
  }

  static ({Object? value, int nextOffset}) read(Uint8List bytes, int offset) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated mark value');
    }
    final tag = bytes[offset];
    final cursor = offset + 1;
    switch (tag) {
      case _null:
        return (value: null, nextOffset: cursor);
      case _false:
        return (value: false, nextOffset: cursor);
      case _true:
        return (value: true, nextOffset: cursor);
      case _int:
        final rec = UVarint.read(bytes, offset: cursor);
        final z = rec.value;
        final v = z.isEven ? z ~/ 2 : -((z + 1) ~/ 2);
        return (value: v, nextOffset: rec.nextOffset);
      case _double:
        if (cursor + 8 > bytes.length) {
          throw const FormatException('Truncated mark double');
        }
        final v = ByteData.sublistView(bytes, cursor, cursor + 8).getFloat64(0);
        return (value: v, nextOffset: cursor + 8);
      case _string:
        final rec =
            UVarint.readBytes(bytes, offset: cursor, what: 'mark string');
        return (value: Wtf8.decode(rec.value), nextOffset: rec.nextOffset);
      default:
        throw FormatException('Unknown mark value tag $tag');
    }
  }
}

// Layout: count: uvarint, then per mark: stamp, then the mark body.
class _MarksSection {
  static Uint8List write(Iterable<_Mark> marks) {
    final sorted = marks.toList()..sort(_Mark.byStamp);
    final out = BytesBuilder(copy: false);
    UVarint.write(sorted.length, out);
    for (final mark in sorted) {
      out.add(mark.stamp.toUint8List());
      _MarkBody.write(
        out,
        key: mark.key,
        value: mark.value,
        start: mark.start,
        end: mark.end,
      );
    }
    return out.toBytes();
  }

  // [blob] is the whole handler blob: the section sits before its 4-byte
  // big-endian length trailer.
  static List<_Mark> read(Uint8List blob) {
    if (blob.length < 4) {
      throw const FormatException('Missing rich text marks trailer');
    }
    final length = ByteData.sublistView(blob, blob.length - 4).getUint32(0);
    final end = blob.length - 4;
    final start = end - length;
    if (start < 0) {
      throw const FormatException('Truncated rich text marks section');
    }
    final bytes = Uint8List.sublistView(blob, start, end);

    final countRec = UVarint.read(bytes, offset: 0);
    var cursor = countRec.nextOffset;
    final marks = <_Mark>[];
    for (var i = 0; i < countRec.value; i++) {
      final stamp = OperationId.readFromBytes(bytes, offset: cursor);
      final body = _MarkBody.read(bytes, cursor + OperationId.byteLength);
      cursor = body.nextOffset;
      marks.add(
        _Mark(
          stamp: stamp,
          key: body.key,
          value: body.value,
          start: body.start,
          end: body.end,
        ),
      );
    }
    return marks;
  }
}
