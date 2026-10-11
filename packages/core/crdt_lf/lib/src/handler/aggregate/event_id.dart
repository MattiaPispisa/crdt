import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// The identity of one event of a [CRDTAggregateHandler]: the change it
/// travels in, its place in that change, and the [part] a migration made of
/// it.
///
/// Every peer computes the same id for the same event, so an entity the
/// event creates can keep it as its identity and later events can name it.
///
/// Binary layout: `stamp: 24 bytes` ([OperationId]), `index: uvarint`,
/// `part: uvarint`.
final class EventId implements Comparable<EventId> {
  /// Creates the id of the [index]-th event of the change [stamp], or of the
  /// [part] a migration made of it.
  const EventId(this.stamp, this.index, {this.part = 0});

  /// Decodes an id written by [toBytes].
  ///
  /// Throws a [FormatException] on a truncated buffer or trailing bytes.
  factory EventId.fromBytes(Uint8List bytes) {
    final read = readFromBytes(bytes);
    if (read.nextOffset != bytes.length) {
      throw const FormatException('Trailing bytes after EventId');
    }
    return read.value;
  }

  /// The id of the change the event travels in.
  final OperationId stamp;

  /// The place of the event in its change, from `0`.
  final int index;

  /// Which of the events a migration made of the written one: `0` for the
  /// written event itself, or for the first event made of it.
  final int part;

  /// The peer that wrote the event.
  PeerId get author => stamp.peerId;

  /// Decodes an id embedded in [bytes] at [offset], and the offset after it.
  ///
  /// Throws a [FormatException] on a truncated buffer.
  static ({EventId value, int nextOffset}) readFromBytes(
    Uint8List bytes, {
    int offset = 0,
  }) {
    final stamp = OperationId.readFromBytes(bytes, offset: offset);
    final index = UVarint.read(bytes, offset: offset + OperationId.byteLength);
    final part = UVarint.read(bytes, offset: index.nextOffset);
    return (
      value: EventId(stamp, index.value, part: part.value),
      nextOffset: part.nextOffset,
    );
  }

  /// Appends this id to [out], in the layout [readFromBytes] reads.
  void writeTo(BytesBuilder out) {
    out.add(stamp.toUint8List());
    UVarint.write(index, out);
    UVarint.write(part, out);
  }

  /// This id as bytes.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    writeTo(out);
    return out.toBytes();
  }

  /// Orders by [stamp], then [index], then [part]: changes in the replay
  /// order, and the events of one change in the order they were written.
  @override
  int compareTo(EventId other) {
    final byStamp = stamp.compareTo(other.stamp);
    if (byStamp != 0) {
      return byStamp;
    }
    final byIndex = index.compareTo(other.index);
    if (byIndex != 0) {
      return byIndex;
    }
    return part.compareTo(other.part);
  }

  @override
  bool operator ==(Object other) =>
      other is EventId &&
      other.stamp == stamp &&
      other.index == index &&
      other.part == part;

  @override
  int get hashCode => Object.hash(stamp, index, part);

  @override
  String toString() => 'EventId($stamp#$index.$part)';
}

/// What [AggregateDefinition.reduce] knows about the event it applies,
/// besides the event itself.
///
/// The same on every peer, so a reducer may read it and stay deterministic.
final class EventContext {
  /// Creates the context of the event [id].
  const EventContext(this.id);

  /// The identity of the event.
  final EventId id;

  /// The peer that wrote the event.
  PeerId get author => id.author;

  @override
  bool operator ==(Object other) => other is EventContext && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EventContext($id)';
}
