import 'dart:typed_data';
import 'package:crdt_lf/src/binary/varint.dart';

/// Versioned binary framing for a list of encoded changes.
///
/// This codec only frames already-encoded per-change byte blobs.
/// The internal per-change layout is defined by the `Change` implementation.
///
/// Format (all integers are unsigned varints unless specified):
/// - magic: 6 bytes: ASCII "CRDTLF"
/// - version: u8 (currently 1)
/// - count: varint
/// - repeated `count` times:
///   - length: varint
///   - payload: `length` bytes
class ChangeCodec {
  ChangeCodec._();

  /// The version of the change codec.
  static const int version = 1;

  /// The magic bytes for the change codec.
  static const List<int> _magic = <int>[67, 82, 68, 84, 76, 70]; // CRDTLF

  /// Encodes a list of change blobs into a single byte array.
  static Uint8List encodeBlobs(List<Uint8List> blobs) {
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(version);
    UVarint.write(blobs.length, out);

    for (final blob in blobs) {
      UVarint.write(blob.length, out);
      out.add(blob);
    }

    return out.toBytes();
  }

  /// Decodes a framed list of change blobs.
  static List<Uint8List> decodeBlobs(Uint8List data) {
    if (data.length < _magic.length + 1) {
      throw const FormatException('Invalid change framing (too short)');
    }

    for (var i = 0; i < _magic.length; i += 1) {
      if (data[i] != _magic[i]) {
        throw const FormatException('Invalid change framing (bad magic)');
      }
    }

    final v = data[_magic.length];
    if (v != version) {
      throw FormatException('Unsupported change framing version: $v');
    }

    var offset = _magic.length + 1;
    final countRec = UVarint.read(data, offset: offset);
    final count = countRec.value;
    offset = countRec.nextOffset;

    final blobs = <Uint8List>[]..length = 0;

    for (var i = 0; i < count; i += 1) {
      final lenRec = UVarint.read(data, offset: offset);
      final len = lenRec.value;
      offset = lenRec.nextOffset;

      final end = offset + len;
      if (end > data.length) {
        throw const FormatException('Truncated change blob');
      }

      blobs.add(Uint8List.sublistView(data, offset, end));
      offset = end;
    }

    if (offset != data.length) {
      throw const FormatException('Trailing bytes after framed changes');
    }

    return blobs;
  }
}
