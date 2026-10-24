// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _AggregateEventsOperation<S extends Object, E> extends Operation {
  _AggregateEventsOperation._({
    required this.events,
    required super.id,
    required super.type,
    required ValueCodec<E> eventCodec,
    Uint8List? body,
    List<({int index, int part})>? places,
  })  : _eventCodec = eventCodec,
        _body = body,
        _places = places;

  factory _AggregateEventsOperation.fromHandler(
    CRDTAggregateHandler<S, E> handler, {
    required List<E> events,
  }) {
    return _AggregateEventsOperation._(
      id: handler.id,
      type: handler._eventsType(handler._definition.version),
      events: List.unmodifiable(events),
      eventCodec: handler._definition.eventCodec,
    );
  }

  factory _AggregateEventsOperation.fromBodyBytes(
    CRDTAggregateHandler<S, E> handler,
    Uint8List body, {
    required int version,
  }) {
    final codec = handler._definition.eventCodec;
    final layout = CRDTAggregateHandler._readLayout(body, 0);
    final count = UVarint.read(body, offset: layout.nextOffset);
    var offset = count.nextOffset;
    final events = <E>[];
    final places = <({int index, int part})>[];
    for (var i = 0; i < count.value; i++) {
      final record = UVarint.readBytes(
        body,
        offset: offset,
        what: 'aggregate event',
      );
      offset = record.nextOffset;
      for (final event in handler._upcastEvent(record.value, version)) {
        events.add(codec.decode(event.bytes));
        places.add((index: i, part: event.part));
      }
    }
    if (offset != body.length) {
      throw const FormatException('Trailing bytes after aggregate events');
    }
    return _AggregateEventsOperation._(
      id: handler.id,
      type: handler._eventsType(version),
      events: List.unmodifiable(events),
      eventCodec: codec,
      body: body,
      places: List.unmodifiable(places),
    );
  }

  final List<E> events;

  final ValueCodec<E> _eventCodec;

  // The bytes a decoded operation was read from. They may be in an older
  // version, which `_eventCodec` cannot write back.
  final Uint8List? _body;

  // Where each event of [events] was written; `null` when [events] is what
  // was written, one event per place.
  final List<({int index, int part})>? _places;

  EventId eventId(int i) {
    final place = _places?[i];
    return place == null
        ? EventId(stamp!, i)
        : EventId(stamp!, place.index, part: place.part);
  }

  @override
  Uint8List toBodyBytes() {
    final body = _body;
    if (body != null) {
      return body;
    }
    final out = BytesBuilder(copy: false);
    UVarint.write(CRDTAggregateHandler._layout, out);
    UVarint.write(events.length, out);
    for (final event in events) {
      UVarint.writeBytes(_eventCodec.encode(event), out);
    }
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'events': events.map((event) => event.toString()).toList(),
      };
}
