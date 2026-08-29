import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';

/// Finds the handler registered under [id] and checks it publishes the shape
/// the caller asked for.
typedef DeltaProviderResolver<V, D extends ComposableDelta<D>>
    = DeltaProvider<V, D> Function(CRDTDocument document, String id);

/// The resolver every widget uses unless it can say something more precise.
///
/// [widgetName] appears in the error, so the reader is told which widget could
/// not find what it needed.
DeltaProvider<V, D> resolveDeltaProvider<V, D extends ComposableDelta<D>>(
  CRDTDocument document,
  String id,
  String widgetName,
) {
  final handler = document.registeredHandlers[id];
  if (handler != null && handler is DeltaProvider<V, D>) {
    // `Handler` is a base class and `DeltaProvider` a base mixin, so the
    // analyzer will not promote across them. The check above is the proof.
    return handler as DeltaProvider<V, D>;
  }
  throw FlutterError(
    '$widgetName<$V, $D> expected the handler registered under id "$id" to '
    'publish deltas of that shape, but found ${handler ?? 'none'}.\n'
    'Check the value/delta pair of the handler you meant to observe; the '
    'table in the CrdtHandlerDeltaListener docs lists them.',
  );
}

/// Follows one handler's delta stream on behalf of a widget.
///
/// It owns what every consumer has to get right: which handler to listen to,
/// where the last read sits in the stream, and which events that read already
/// covers. The widget keeps only what to do with the value.
class HandlerDeltaSubscription<V, D extends ComposableDelta<D>> {
  /// Creates a subscription that is not attached to anything yet.
  HandlerDeltaSubscription({
    required this.resolve,
    required this.onReset,
    required this.onDelta,
    required this.isAlive,
    required this.seed,
    this.origin,
  });

  /// How to find the provider. A widget that can give a better error than
  /// [resolveDeltaProvider] passes its own.
  final DeltaProviderResolver<V, D> resolve;

  /// Called with a value that was just read, and why it had to be read.
  ///
  /// With [seed] on, it is **not** called for the reset that opens the
  /// subscription: [syncTo] returned that value already.
  final void Function(DeltaSyncPoint<V> point, ResetCause cause) onReset;

  /// Called once per change, with what that change did.
  final void Function(HandlerDelta<D> event) onDelta;

  /// Whether the owner still wants events — a `State`'s `mounted`.
  final bool Function() isAlive;

  /// What the owner tags its own writes with; `null` when it never writes.
  ///
  /// A delta carrying it is the owner's own echo, already in its copy, so
  /// [onDelta] is skipped — [synced] still advances. Deltas only: a
  /// [HandlerReset] carries no origin and always reaches [onReset].
  final Object? origin;

  /// Whether [syncTo] reads the value as it attaches, so the first frame shows
  /// the document instead of an empty one.
  ///
  /// A widget that hands the value to a **user** callback leaves it off:
  /// [syncTo] runs inside `build`, and that callback may call `setState`.
  final bool seed;

  /// The document and handler id this is attached to, or `null` before the
  /// first attach.
  (CRDTDocument, String)? _target;

  /// Set by the first [syncTo]; reading it before then is a mistake the
  /// `late` reports plainly.
  late DeltaProvider<V, D> _provider;
  StreamSubscription<HandlerUpdate<D>>? _subscription;

  /// The last point of the stream this consumer accounts for. Nothing has
  /// arrived yet at `-1`; sequence numbers start at one.
  int _synced = -1;

  /// The handler being followed, resolved once per attachment: a handler id is
  /// registered at most once and never removed.
  DeltaProvider<V, D> get provider => _provider;

  /// The last point of the stream this consumer accounts for.
  int get synced => _synced;

  /// The point the stream has **published**.
  ///
  /// Delivery is a microtask later, so this can be ahead of [synced] even
  /// though nothing was missed.
  int get publishedSeq => provider.deltaSeq;

  /// Attaches to [id] on [document], if that is not already what it follows.
  ///
  /// Returns the value read while attaching, and `null` without [seed]. Call it
  /// from `build`: it covers a new document and a new id alike, so no consumer
  /// needs `didUpdateWidget`.
  ///
  /// [onBeforeAttach] runs after the old subscription is dropped and before the
  /// new handler is touched, for state tied to the old one.
  DeltaSyncPoint<V>? syncTo(
    CRDTDocument document,
    String id, {
    VoidCallback? onBeforeAttach,
  }) {
    final current = _target;
    if (current != null &&
        identical(current.$1, document) &&
        current.$2 == id) {
      return null;
    }

    unawaited(_subscription?.cancel());
    _target = (document, id);
    onBeforeAttach?.call();

    final target = _provider = resolve(document, id);
    _synced = -1;

    final point = seed ? readSynced() : null;

    // The read comes first, and in this same turn: `watch()` raises the
    // sequence as it starts listening, so the reset that follows is exactly
    // one past what was read and [_onUpdate] can drop it.
    _subscription = target.watch().listen(_onUpdate);
    return point;
  }

  /// Reads the value and moves [synced] to the point it reflects.
  ///
  /// One step: two would let an event land in between and be applied on top of
  /// a value that already holds it.
  DeltaSyncPoint<V> readSynced() {
    final point = provider.readSynced();
    _synced = point.seq;
    return point;
  }

  /// Accounts for everything published so far without reading anything, for a
  /// consumer that moved its own copy by hand.
  void markSyncedToPublished() => _synced = provider.deltaSeq;

  /// Stops listening. The target goes with it, so a later [syncTo] to the same
  /// handler attaches again instead of taking the early exit and going quiet.
  void cancel() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _target = null;
  }

  void _onUpdate(HandlerUpdate<D> update) {
    if (!isAlive()) {
      return;
    }
    switch (update) {
      case HandlerReset<D>():
        if (seed &&
            update.cause == ResetCause.initial &&
            update.seq == _synced + 1) {
          // [syncTo] read the value and subscribed in one turn, and this is
          // the very next event: what this reset asks for is already held.
          _synced = update.seq;
          return;
        }
        // The only place that reads the whole value again.
        onReset(readSynced(), update.cause);
      case HandlerDelta<D>():
        if (update.seq <= _synced) {
          // Already inside the value the last read handed over.
          return;
        }
        // Move first, then report: a consumer may write from inside `onDelta`
        // and account for its own echo, which an advance on the way out would
        // undo.
        _synced = update.seq;
        final tag = origin;
        if (tag != null && identical(update.origin, tag)) {
          // The owner's own write, already in its copy.
          return;
        }
        onDelta(update);
    }
  }
}
