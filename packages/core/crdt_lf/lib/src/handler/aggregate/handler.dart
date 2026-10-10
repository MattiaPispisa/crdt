import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

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
/// or none. Two calls are two changes, even inside a transaction.
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
  }) : this._fromSpec(
          doc,
          id,
          spec: spec<S, E>(definition),
          definition: definition,
        );

  CRDTAggregateHandler._fromSpec(
    super.doc,
    this._id, {
    required super.spec,
    required AggregateDefinition<S, E> definition,
  })  : _definition = definition,
        _migrations = _migrationsByVersion(definition),
        _eventTypes = {};

  final String _id;
  final AggregateDefinition<S, E> _definition;
  final Map<int, AggregateMigration> _migrations;

  /// The kind [definition] describes, tagged with its
  /// [AggregateDefinition.handlerType].
  ///
  /// Throws an [ArgumentError] when [AggregateDefinition.version] or
  /// [AggregateDefinition.minReadableVersion] fall outside
  /// `1..AggregateDefinition.maxVersion`, or when a migration between the two
  /// is missing or given twice.
  static HandlerSpec<CRDTAggregateHandler<S, E>> spec<S extends Object, E>(
    AggregateDefinition<S, E> definition,
  ) {
    _migrationsByVersion(definition);
    return HandlerSpec<CRDTAggregateHandler<S, E>>(
      definition.handlerType,
      (doc, id) => CRDTAggregateHandler<S, E>(doc, id, definition: definition),
      formats: HandlerFormats(
        operationKinds: {
          for (var v = definition.minReadableVersion;
              v <= definition.version;
              v++)
            _kindOf(v),
        },
        blobVersions: BlobVersionRange(
          definition.minReadableVersion,
          definition.version,
        ),
      ),
    );
  }

  static int _kindOf(int version) =>
      AggregateDefinition.firstEventKind + version - 1;

  static Map<int, AggregateMigration> _migrationsByVersion(
    AggregateDefinition<Object, Object?> definition,
  ) {
    final version = definition.version;
    final minReadable = definition.minReadableVersion;
    if (version < 1 || version > AggregateDefinition.maxVersion) {
      throw ArgumentError.value(
        version,
        'version',
        'must be in 1..${AggregateDefinition.maxVersion}',
      );
    }
    if (minReadable < 1 || minReadable > version) {
      throw ArgumentError.value(
        minReadable,
        'minReadableVersion',
        'must be in 1..$version',
      );
    }

    final byVersion = <int, AggregateMigration>{};
    for (final migration in definition.migrations) {
      if (byVersion.containsKey(migration.from)) {
        throw ArgumentError(
          'Two migrations of ${definition.handlerType} start from version '
          '${migration.from}.',
        );
      }
      byVersion[migration.from] = migration;
    }
    for (var from = minReadable; from < version; from++) {
      if (!byVersion.containsKey(from)) {
        throw ArgumentError(
          '${definition.handlerType} reads version $minReadable but has no '
          'migration from version $from to ${from + 1}.',
        );
      }
    }
    return byVersion;
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
    for (var v = _definition.minReadableVersion; v <= _definition.version; v++)
      _kindOf(v): (body) => _AggregateEventsOperation<S, E>.fromBodyBytes(
            this,
            body,
            version: v,
          ),
  };

  /// Writes [event]; the same as `dispatchAll([event])`.
  void dispatch(E event) => dispatchAll([event]);

  /// Writes [events], in order, as one change. Does nothing when [events] is
  /// empty.
  ///
  /// The events are written in the current [AggregateDefinition.version].
  void dispatchAll(List<E> events) {
    if (events.isEmpty) {
      return;
    }
    doc.registerOperation(
      _AggregateEventsOperation<S, E>.fromHandler(this, events: events),
    );
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
        state = _fold(state, operation);
      }
    }
    return state;
  }

  S _fold(S state, _AggregateEventsOperation<S, E> operation) {
    final stamp = operation.stamp!;
    var current = state;
    for (var i = 0; i < operation.events.length; i++) {
      current = _definition.reduce(
        current,
        operation.events[i],
        EventContext(EventId(stamp, i)),
      );
    }
    return current;
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
    if (sink != null) {
      final stamp = operation.stamp!;
      sink.add(
        AggregateDelta<S, E>(
          previous: state,
          current: next,
          events: [
            for (var i = 0; i < operation.events.length; i++)
              AggregateEvent<E>(
                operation.events[i],
                EventContext(EventId(stamp, i)),
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

    final stamp = operation.stamp!;
    var state = value;
    final groups = <List<E>>[];
    for (var i = 0; i < operation.events.length; i++) {
      final event = operation.events[i];
      final context = EventContext(EventId(stamp, i));
      groups.add(definition.invert(state, event, context));
      state = definition.reduce(state, event, context);
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
  int get minReadableSnapshotBlobVersion => _definition.minReadableVersion;

  @override
  Uint8List getSnapshotState() {
    final out = snapshotHeader()..add(_definition.stateCodec.encode(value));
    return out.toBytes();
  }

  S _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return _definition.initial();
    }
    final header = readSnapshotHeader(snapshot);
    var bytes = Uint8List.sublistView(snapshot, header.offset);
    for (var from = header.version; from < _definition.version; from++) {
      bytes = _migrations[from]!.upState(bytes);
    }
    return _definition.stateCodec.decode(bytes);
  }

  Uint8List _upcastEvent(Uint8List event, int version) {
    var bytes = event;
    for (var from = version; from < _definition.version; from++) {
      bytes = _migrations[from]!.upEvent(bytes);
    }
    return bytes;
  }

  @override
  S applyDelta(S base, AggregateDelta<S, E> delta) => delta.apply(base);

  @override
  String toString() => 'CRDTAggregateHandler($handlerType#$_id)';
}
