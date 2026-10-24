// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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
/// final class CarAggregate extends AggregateDefinition<Car, CarEvent> {
///   const CarAggregate();
///
///   @override
///   String get handlerType => 'car';
///
///   @override
///   Car initial(String id) => Car(licensePlate: id);
///
///   @override
///   Car reduce(Car state, CarEvent event, EventContext context) =>
///       switch (event) {
///         OwnerChanged(:final owner) => state.copyWith(owner: owner),
///         MaintenanceLogged(:final note) =>
///           state.copyWith(lastMaintenance: note),
///       };
///
///   @override
///   ValueCodec<CarEvent> get eventCodec => const CarEventCodec();
///
///   @override
///   ValueCodec<Car> get stateCodec => const CarCodec();
/// }
/// ```
abstract base class AggregateDefinition<S extends Object, E> {
  /// Const constructor for subclasses.
  const AggregateDefinition();

  /// The highest [version] a definition can declare.
  static const int maxVersion = OperationType.maxKind - firstEventKind + 1;

  /// The operation kind the events of version 1 travel under. Version `v`
  /// travels under `firstEventKind + v - 1`; the kinds below are reserved.
  static const int firstEventKind = 16;

  /// {@macro handler_type_tag}
  String get handlerType;

  /// The state of the aggregate [id] before any event touches it.
  S initial(String id);

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
  ///
  /// Throw to refuse [event]. [CRDTAggregateHandler.dispatchAll] then throws
  /// the same error and writes nothing. A change holding an event that throws
  /// is skipped whole, on every peer: this is how an event that a concurrent
  /// one made invalid is dropped.
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

  /// The steps that bring older data up to [version], one step per version.
  ///
  /// This build reads every version an unbroken chain of steps leads up from;
  /// data in an older version is refused. Drop the steps below a version once
  /// no peer and no stored document holds data in it any more.
  ///
  /// [CRDTAggregateHandler.spec] throws an [ArgumentError] on two steps from
  /// one version, or on a step that does not lead up to [version].
  List<AggregateMigration> get migrations => const [];
}

/// An [AggregateDefinition] whose events can be undone with
/// [CRDTUndoManager].
abstract base class InvertibleAggregateDefinition<S extends Object, E>
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
abstract base class AggregateMigration {
  /// Const constructor for subclasses.
  const AggregateMigration();

  /// The version this step reads.
  int get from;

  /// The events that [event], written in version [from], becomes in the next
  /// version: an empty list drops it, several events split it.
  ///
  /// The first one keeps the [EventId] of [event]; each other one gets an
  /// [EventId.part] of its own. No id ever moves, so the entities an older
  /// version created keep their identity.
  List<Uint8List> upEvent(Uint8List event);

  /// [state], a snapshot state written in version [from], rewritten in the
  /// next version.
  ///
  /// It must give the state that replaying the events through [upEvent] gives,
  /// or a peer that starts from a snapshot diverges from a peer that replays
  /// the history.
  Uint8List upState(Uint8List state);
}
