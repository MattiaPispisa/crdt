import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// Describes a kind of aggregate: its state [S], its events [E], and how an
/// event moves the state.
///
/// A [CRDTAggregateHandler] replays the events of every peer in the replay
/// order, `(HLC, author)`, through [reduce]. Peers that hold the same events
/// therefore hold the same state, whatever [reduce] does — as long as it is
/// deterministic.
///
/// ```dart
/// class AssetAggregate extends AggregateDefinition<Asset, AssetEvent> {
///   const AssetAggregate();
///
///   @override
///   String get handlerType => 'asset';
///
///   @override
///   Asset initial() => const Asset();
///
///   @override
///   Asset reduce(Asset state, AssetEvent event, EventContext context) =>
///       switch (event) {
///         Renamed(:final name) => state.copyWith(displayName: name),
///         NoteAdded(:final text) => state.addNote(Note(context.id, text)),
///       };
///
///   @override
///   ValueCodec<AssetEvent> get eventCodec => const AssetEventCodec();
///
///   @override
///   ValueCodec<Asset> get stateCodec => const AssetCodec();
/// }
/// ```
abstract class AggregateDefinition<S extends Object, E> {
  /// Const constructor for subclasses.
  const AggregateDefinition();

  /// The highest [version] a definition can declare.
  static const int maxVersion = OperationType.maxKind - firstEventKind + 1;

  /// The operation kind the events of version 1 travel under. Version `v`
  /// travels under `firstEventKind + v - 1`.
  static const int firstEventKind = 4;

  /// {@macro handler_type_tag}
  String get handlerType;

  /// The state of an aggregate no event has touched yet.
  S initial();

  /// The state [state] becomes once [event] is applied.
  ///
  /// Must be pure and deterministic: no clock, no randomness, no iteration
  /// over an unordered collection. Every peer calls it on the same events in
  /// the same order and must get the same result; read time and author from
  /// [context] instead.
  ///
  /// Address the parts of the state by identity, never by position: an event
  /// is applied after the events other peers wrote concurrently. An entity an
  /// event creates can take [EventContext.id] as its identity.
  ///
  /// Return a new state rather than changing [state]: the handler hands
  /// [state] out as its value, and deltas keep both ends.
  S reduce(S state, E event, EventContext context);

  /// Encodes and decodes the events of the current [version].
  ///
  /// The bytes it writes are the wire format of the events: a change to the
  /// layout is a new [version].
  ValueCodec<E> get eventCodec;

  /// Encodes and decodes the state of the current [version], for snapshots.
  ///
  /// It has to keep every identity [reduce] reads, or an event written after
  /// a snapshot finds nothing to address.
  ValueCodec<S> get stateCodec;

  /// The format of the events and of the state this build reads, and writes.
  ///
  /// Starts at `1`, up to [maxVersion]. Raise it when [eventCodec] or
  /// [stateCodec] change their bytes, or when [reduce] gives an event a new
  /// meaning, and add a migration from the previous version.
  int get version => 1;

  /// The oldest version this build still reads; defaults to [version].
  ///
  /// Data in an older version is refused. Raise it only once no peer and no
  /// stored document holds events or snapshots of that version any more —
  /// for example after every replica took a snapshot that pruned them.
  int get minReadableVersion => version;

  /// The steps that bring data from [minReadableVersion] up to [version],
  /// one step per version.
  ///
  /// A step for every version in between is required:
  /// [CRDTAggregateHandler.spec] throws an [ArgumentError] on a gap or on two
  /// steps from the same version.
  List<AggregateMigration> get migrations => const [];
}

/// An [AggregateDefinition] whose events can be undone with
/// [CRDTUndoManager].
abstract class InvertibleAggregateDefinition<S extends Object, E>
    extends AggregateDefinition<S, E> {
  /// Const constructor for subclasses.
  const InvertibleAggregateDefinition();

  /// The events that take [event] back, read against [before], the state as it
  /// is before [event] is applied. Empty when there is nothing to undo.
  ///
  /// Name identities, never positions: the undo is written later, after other
  /// peers may have changed the aggregate. To bring back an entity [event]
  /// removed, write an event that recreates it under its own id, so the undo
  /// of the event that created it still finds it.
  List<E> invert(S before, E event, EventContext context);
}

/// One step that brings the data of an aggregate from version [from] to
/// `from + 1`.
///
/// A step runs every time data of version [from] is read: the history keeps
/// the bytes each peer wrote, so it is never rewritten. A step is therefore
/// pure and deterministic, and once released it never changes.
abstract class AggregateMigration {
  /// Const constructor for subclasses.
  const AggregateMigration();

  /// The version this step reads.
  int get from;

  /// [event], written in version [from], rewritten in the next version.
  ///
  /// One event in, one event out: the [EventId] of an event is its place in
  /// its change, so dropping or splitting one would move the ids of the
  /// events after it.
  Uint8List upEvent(Uint8List event);

  /// [state], a snapshot state written in version [from], rewritten in the
  /// next version.
  ///
  /// It must give the state that replaying the events through [upEvent] gives,
  /// or a peer that starts from a snapshot diverges from a peer that replays
  /// the history.
  Uint8List upState(Uint8List state);
}
