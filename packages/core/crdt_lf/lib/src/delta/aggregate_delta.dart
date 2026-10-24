// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/src/delta/handler_update.dart';
import 'package:crdt_lf/src/handler/aggregate/event_id.dart';

/// One event an aggregate applied, with its context.
final class AggregateEvent<E> {
  /// Pairs [event] with its [context].
  const AggregateEvent(this.event, this.context);

  /// The event.
  final E event;

  /// Where the event comes from.
  final EventContext context;

  @override
  bool operator ==(Object other) =>
      other is AggregateEvent<E> &&
      other.event == event &&
      other.context == context;

  @override
  int get hashCode => Object.hash(event, context);

  @override
  String toString() => 'AggregateEvent($event, ${context.id})';
}

/// How an aggregate's state moved: from [previous] to [current], through
/// [events].
final class AggregateDelta<S, E>
    implements ComposableDelta<AggregateDelta<S, E>> {
  /// The state went from [previous] to [current] through [events].
  const AggregateDelta({
    required this.previous,
    required this.current,
    required this.events,
  });

  /// The state before the events.
  final S previous;

  /// The state after the events.
  final S current;

  /// The events applied, in the order they were applied.
  final List<AggregateEvent<E>> events;

  /// Whether the two ends are equal, by `==`: events that changed nothing.
  @override
  bool get isEmpty => previous == current;

  /// Whether this delta moves something.
  bool get isNotEmpty => !isEmpty;

  /// The delta that has the same effect as this one followed by [next]: the
  /// two outer ends, and every event of both.
  @override
  AggregateDelta<S, E> compose(AggregateDelta<S, E> next) => AggregateDelta(
        previous: previous,
        current: next.current,
        events: [...events, ...next.events],
      );

  /// What the state is once this delta is applied, which is [current].
  ///
  /// [base] is ignored: the delta already carries the whole state.
  S apply(S base) => current;

  @override
  String toString() =>
      'AggregateDelta($previous -> $current, ${events.length} events)';
}
