part of 'handler.dart';

class _AggregateEventsOperation<S extends Object, E> extends Operation {
  _AggregateEventsOperation._({
    required this.events,
    required super.id,
    required super.type,
    required ValueCodec<E> eventCodec,
    Uint8List? body,
  })  : _eventCodec = eventCodec,
        _body = body;

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
    final count = UVarint.read(body, offset: 0);
    var offset = count.nextOffset;
    final events = <E>[];
    for (var i = 0; i < count.value; i++) {
      final record = UVarint.readBytes(
        body,
        offset: offset,
        what: 'aggregate event',
      );
      offset = record.nextOffset;
      events.add(codec.decode(handler._upcastEvent(record.value, version)));
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
    );
  }

  final List<E> events;

  final ValueCodec<E> _eventCodec;

  // The bytes a decoded operation was read from. They may be in an older
  // version, which `_eventCodec` cannot write back.
  final Uint8List? _body;

  @override
  Uint8List toBodyBytes() {
    final body = _body;
    if (body != null) {
      return body;
    }
    final out = BytesBuilder(copy: false);
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
