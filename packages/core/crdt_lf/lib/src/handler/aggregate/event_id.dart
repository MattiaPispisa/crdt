import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// The identity of one event of a [CRDTAggregateHandler]: the change it
/// travels in, and its place in that change.
///
/// Every peer computes the same id for the same event, so an entity the
/// event creates can keep it as its identity and later events can name it.
///
/// Binary layout: `stamp: 24 bytes` ([OperationId]), `index: uvarint`.
class EventId implements Comparable<EventId> {
  /// Creates the id of the [index]-th event of the change [stamp].
  const EventId(this.stamp, this.index);

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
    return (value: EventId(stamp, index.value), nextOffset: index.nextOffset);
  }

  /// Appends this id to [out], in the layout [readFromBytes] reads.
  void writeTo(BytesBuilder out) {
    out.add(stamp.toUint8List());
    UVarint.write(index, out);
  }

  /// This id as bytes.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    writeTo(out);
    return out.toBytes();
  }

  /// Orders by [stamp], then by [index]: the order the events are applied in.
  @override
  int compareTo(EventId other) {
    final byStamp = stamp.compareTo(other.stamp);
    if (byStamp != 0) {
      return byStamp;
    }
    return index.compareTo(other.index);
  }

  @override
  bool operator ==(Object other) =>
      other is EventId && other.stamp == stamp && other.index == index;

  @override
  int get hashCode => Object.hash(stamp, index);

  @override
  String toString() => 'EventId($stamp#$index)';
}

/// What [AggregateDefinition.reduce] knows about the event it applies,
/// besides the event itself.
///
/// The same on every peer, so a reducer may read it and stay deterministic.
class EventContext {
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
