import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

typedef _Versions = ({int oldest, Map<int, AggregateMigration> steps});

/// # CRDT Aggregate
///
/// ## Description
/// One aggregate — an object with several fields that changes over time —
/// built from the events written on it. Its [AggregateDefinition] says what
/// the events are and how each one moves the state.
///
/// One handler holds one aggregate: the asset `asset-42` is the handler
/// `asset-42`. Many aggregates of one kind share one definition and one tag.
///
/// ## Convergence
/// The state is the events of every peer applied in the replay order,
/// `(HLC, author)`. Two peers with the same events hold the same state. Of two
/// concurrent events, the one later in that order is applied last, so a
/// concurrent write to the same field is won by the later stamp.
///
/// An event that arrives older than the newest one already applied makes the
/// next read replay this aggregate's history since the last snapshot.
///
/// ## Atomicity
/// [dispatchAll] writes its events in one change: a peer receives all of them
/// or none, and applies all of them or none when
/// [AggregateDefinition.reduce] refuses one. Two calls are two changes, even
/// inside a transaction.
///
/// ## Versions
/// Events and snapshot state carry the [AggregateDefinition.version] they
/// were written in, and older data is brought up to date with
/// [AggregateDefinition.migrations] as it is read. A peer that meets a newer
/// version refuses it, and a sync layer comparing capabilities sees the
/// mismatch first.
///
/// ## Example
/// ```dart
/// final asset = doc.handler(
///   CRDTAggregateHandler.spec(const AssetAggregate()),
///   'asset-42',
/// );
/// asset.dispatchAll([const Renamed('P-101'), const NoteAdded('Installed')]);
/// print(asset.value.displayName); // P-101
/// ```
base class CRDTAggregateHandler<S extends Object, E> extends Handler<S>
    with DeltaProvider<S, AggregateDelta<S, E>> {
  /// Creates the aggregate [id] of the kind [definition] describes.
  ///
  /// Throws an [ArgumentError] when [definition] declares versions or
  /// migrations that do not fit together; see [spec].
  CRDTAggregateHandler(
    BaseCRDTDocument doc,
    String id, {
    required AggregateDefinition<S, E> definition,
  }) : this._(
          doc,
          id,
          definition: definition,
          versions: _versionsOf(definition),
        );

  CRDTAggregateHandler._(
    super.doc,
    this._id, {
    required AggregateDefinition<S, E> definition,
    required _Versions versions,
  })  : _definition = definition,
        _oldestVersion = versions.oldest,
        _migrations = versions.steps,
        _eventTypes = {},
        super(spec: _specOf(definition, versions));

  final String _id;
  final AggregateDefinition<S, E> _definition;
  final int _oldestVersion;
  final Map<int, AggregateMigration> _migrations;

  // Written before the events and the snapshot state, so a later release can
  // frame them differently and an older build refuses that framing by name.
  static const int _layout = 0;

  /// The kind [definition] describes, tagged with its
  /// [AggregateDefinition.handlerType].
  ///
  /// Throws an [ArgumentError] when [AggregateDefinition.version] falls
  /// outside `1..AggregateDefinition.maxVersion`, or when
  /// [AggregateDefinition.migrations] repeat a version or hold a step that
  /// does not lead up to the current one.
  static HandlerSpec<CRDTAggregateHandler<S, E>> spec<S extends Object, E>(
    AggregateDefinition<S, E> definition,
  ) =>
      _specOf(definition, _versionsOf(definition));

  static HandlerSpec<CRDTAggregateHandler<S, E>> _specOf<S extends Object, E>(
    AggregateDefinition<S, E> definition,
    _Versions versions,
  ) =>
      HandlerSpec<CRDTAggregateHandler<S, E>>(
        definition.handlerType,
        (doc, id) => CRDTAggregateHandler<S, E>._(
          doc,
          id,
          definition: definition,
          versions: versions,
        ),
        formats: HandlerFormats(
          operationKinds: {
            for (var v = versions.oldest; v <= definition.version; v++)
              _kindOf(v),
          },
          blobVersions: BlobVersionRange(versions.oldest, definition.version),
        ),
      );

  static int _kindOf(int version) =>
      AggregateDefinition.firstEventKind + version - 1;

  static _Versions _versionsOf(
    AggregateDefinition<Object, Object?> definition,
  ) {
    final type = definition.handlerType;
    final version = definition.version;
    if (version < 1 || version > AggregateDefinition.maxVersion) {
      throw ArgumentError.value(
        version,
        'version',
        'must be in 1..${AggregateDefinition.maxVersion}',
      );
    }

    final steps = <int, AggregateMigration>{};
    for (final migration in definition.migrations) {
      if (steps.containsKey(migration.from)) {
        throw ArgumentError(
          'Two migrations of $type start from version ${migration.from}.',
        );
      }
      steps[migration.from] = migration;
    }

    var oldest = version;
    while (steps.containsKey(oldest - 1)) {
      oldest--;
    }
    for (final from in steps.keys) {
      if (from >= version) {
        throw ArgumentError(
          '$type has a migration from version $from, but its version is '
          '$version.',
        );
      }
      if (from < oldest) {
        throw ArgumentError(
          '$type has a migration from version $from but none from version '
          '${oldest - 1} to $oldest.',
        );
      }
    }
    return (oldest: oldest, steps: steps);
  }

  @override
  String get id => _id;

  /// The kind of aggregate this is.
  AggregateDefinition<S, E> get definition => _definition;

  final Map<int, OperationType> _eventTypes;

  // Stamped: the reducer reads the change id through `EventContext`. That
  // also keeps `Compound` from fusing two dispatches into one change.
  OperationType _eventsType(int version) =>
      _eventTypes[version] ??= OperationType.custom(
        this,
        kind: _kindOf(version),
        name: 'events.v$version',
        stamped: true,
      );

  @override
  late final OperationDecoders operationDecoders = {
    for (var v = _oldestVersion; v <= _definition.version; v++)
      _kindOf(v): (body) => _AggregateEventsOperation<S, E>.fromBodyBytes(
            this,
            body,
            version: v,
          ),
  };

  /// Writes [event] and returns its id; the same as `dispatchAll([event])`.
  EventId dispatch(E event) => dispatchAll([event]).single;

  /// Writes [events], in order, as one change, and returns their ids. Does
  /// nothing when [events] is empty.
  ///
  /// The events are written in the current [AggregateDefinition.version].
  /// Throws what [AggregateDefinition.reduce] throws, and then writes nothing.
  List<EventId> dispatchAll(List<E> events) {
    if (events.isEmpty) {
      return const [];
    }

    // The stamp is minted at registration: the ids this check hands out are
    // thrown away with its result.
    final provisional = OperationId(doc.peerId, doc.hlc);
    var state = value;
    for (var i = 0; i < events.length; i++) {
      state = _definition.reduce(
        state,
        events[i],
        EventContext(EventId(provisional, i)),
      );
    }

    final operation =
        _AggregateEventsOperation<S, E>.fromHandler(this, events: events);
    doc.registerOperation(operation);
    return [for (var i = 0; i < events.length; i++) operation.eventId(i)];
  }

  /// The current state.
  ///
  /// The same object stays cached until the next event: treat it as
  /// read-only.
  @override
  S get value {
    final cached = cachedState;
    if (cached != null) {
      return cached;
    }
    final computed = _computeState();
    updateCachedState(computed);
    return computed;
  }

  S _computeState() {
    var state = _initialState();
    for (final operation in operations()) {
      if (operation is _AggregateEventsOperation<S, E>) {
        state = _fold(state, operation) ?? state;
      }
    }
    return state;
  }

  S? _fold(S state, _AggregateEventsOperation<S, E> operation) {
    S? current = state;
    for (var i = 0; i < operation.events.length && current != null; i++) {
      current = _reduce(
        current,
        operation.events[i],
        EventContext(operation.eventId(i)),
      );
    }
    return current;
  }

  S? _reduce(S state, E event, EventContext context) {
    try {
      return _definition.reduce(state, event, context);
    } catch (_) {
      // A deterministic reducer refuses the same event on every peer, so
      // skipping it keeps the peers equal.
      return null;
    }
  }

  @override
  S? incrementCachedState({
    required Operation operation,
    required S state,
    DeltaSink<Object?>? sink,
  }) {
    if (operation is! _AggregateEventsOperation<S, E>) {
      return state;
    }
    final next = _fold(state, operation);
    if (next == null) {
      return state;
    }
    if (sink != null) {
      sink.add(
        AggregateDelta<S, E>(
          previous: state,
          current: next,
          events: [
            for (var i = 0; i < operation.events.length; i++)
              AggregateEvent<E>(
                operation.events[i],
                EventContext(operation.eventId(i)),
              ),
          ],
        ),
      );
    }
    return next;
  }

  @override
  bool get invertible => _definition is InvertibleAggregateDefinition<S, E>;

  @override
  List<Operation> invert(Operation operation) {
    final definition = _definition;
    if (definition is! InvertibleAggregateDefinition<S, E> ||
        operation is! _AggregateEventsOperation<S, E>) {
      return const [];
    }

    var state = value;
    final groups = <List<E>>[];
    for (var i = 0; i < operation.events.length; i++) {
      final event = operation.events[i];
      final context = EventContext(operation.eventId(i));
      groups.add(definition.invert(state, event, context));
      final next = _reduce(state, event, context);
      if (next == null) {
        return const [];
      }
      state = next;
    }

    // The last event is undone first, each against the state it saw.
    final inverse = [for (final group in groups.reversed) ...group];
    if (inverse.isEmpty) {
      return const [];
    }
    return [_AggregateEventsOperation<S, E>.fromHandler(this, events: inverse)];
  }

  @override
  int get snapshotBlobVersion => _definition.version;

  @override
  int get minReadableSnapshotBlobVersion => _oldestVersion;

  @override
  Uint8List getSnapshotState() {
    final out = snapshotHeader();
    UVarint.write(_layout, out);
    out.add(_definition.stateCodec.encode(value));
    return out.toBytes();
  }

  S _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return _definition.initial(_id);
    }
    final header = readSnapshotHeader(snapshot);
    final layout = _readLayout(snapshot, header.offset);
    var bytes = Uint8List.sublistView(snapshot, layout.nextOffset);
    for (var from = header.version; from < _definition.version; from++) {
      bytes = _migrations[from]!.upState(bytes);
    }
    return _definition.stateCodec.decode(bytes);
  }

  static UVarintResult _readLayout(
    Uint8List bytes,
    int offset,
  ) {
    final layout = UVarint.read(bytes, offset: offset);
    if (layout.value != _layout) {
      throw FormatException('Unknown aggregate layout ${layout.value}');
    }
    return layout;
  }

  List<({Uint8List bytes, int part})> _upcastEvent(
    Uint8List event,
    int version,
  ) {
    var events = [(bytes: event, part: 0)];
    var nextPart = 1;
    for (var from = version; from < _definition.version; from++) {
      final migration = _migrations[from]!;
      final next = <({Uint8List bytes, int part})>[];
      for (final event in events) {
        final products = migration.upEvent(event.bytes);
        for (var i = 0; i < products.length; i++) {
          // The first product stands for the event it came from, and a new
          // one takes a part no other version handed out: ids never move.
          final part = i == 0 ? event.part : nextPart++;
          next.add((bytes: products[i], part: part));
        }
      }
      events = next;
    }
    return events;
  }

  @override
  S applyDelta(S base, AggregateDelta<S, E> delta) => delta.apply(base);

  @override
  String toString() => 'CRDTAggregateHandler($handlerType#$_id)';
}
